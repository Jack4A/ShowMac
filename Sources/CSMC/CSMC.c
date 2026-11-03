// AppleSMC ABI reference: beltex/SMCKit (MIT); license in Resources/SMCKit-LICENSE.txt.
#include "CSMC.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/pwr_mgt/IOPM.h>
#include <IOKit/kext/KextManager.h>
#include <IOKit/ps/IOPowerSources.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <libproc.h>
#include <signal.h>
#include <string.h>
#include <math.h>

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } Version;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } PLimit;
typedef struct { uint32_t size, type; uint8_t attributes; } KeyInfo;
typedef struct {
    uint32_t key; Version version; PLimit limit; KeyInfo info;
    uint8_t result, status, command; uint32_t data32; uint8_t bytes[32];
} SMCMessage;
_Static_assert(sizeof(SMCMessage) == 80, "AppleSMC ABI must be 80 bytes");

static uint32_t fourcc(const char *s) {
    return (uint32_t)(uint8_t)s[0]<<24 | (uint32_t)(uint8_t)s[1]<<16 |
           (uint32_t)(uint8_t)s[2]<<8 | (uint32_t)(uint8_t)s[3];
}
static int call(uint32_t connection, SMCMessage *in, SMCMessage *out) {
    size_t size = sizeof(*out);
    kern_return_t r = IOConnectCallStructMethod(connection, 2, in, sizeof(*in), out, &size);
    if (r != KERN_SUCCESS) return (int)r;
    if (size != sizeof(*out)) return -1;
    return out->result ? (int)out->result : 0;
}
uint32_t ts_smc_open(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 0;
    io_connect_t connection = 0;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    return result == KERN_SUCCESS ? connection : 0;
}
void ts_smc_close(uint32_t connection) { if (connection) IOServiceClose(connection); }
int ts_smc_key_at_index(uint32_t connection,uint32_t index,char *key) {
    if (!connection || !key) return -1;
    SMCMessage in={0},out={0};in.command=8;in.data32=index;
    int result=call(connection,&in,&out);if(result) return result;
    key[0]=(char)(out.key>>24);key[1]=(char)(out.key>>16);key[2]=(char)(out.key>>8);key[3]=(char)out.key;key[4]=0;
    return 0;
}
int ts_smc_read(uint32_t connection, const char *key, TSValue *value) {
    if (!connection || !key || strlen(key) != 4 || !value) return -1;
    SMCMessage in = {0}, out = {0};
    in.key = fourcc(key); in.command = 9;
    int r = call(connection, &in, &out);
    if (r) return r;
    if (!out.info.size || out.info.size > 32) return -2;
    value->size = out.info.size; value->type = out.info.type;
    in.info.size = value->size; in.command = 5;
    memset(&out, 0, sizeof(out));
    r = call(connection, &in, &out);
    if (!r) memcpy(value->bytes, out.bytes, 32);
    return r;
}
int ts_smc_write(uint32_t connection, const char *key, const TSValue *value) {
    if (!connection || !key || strlen(key) != 4 || !value || value->size > 32 || !value->size) return -1;
    // The bridge deliberately only permits fan mode/target keys, never arbitrary SMC writes.
    int fanKey = key[0]=='F' && key[1]>='0' && key[1]<='9' &&
                 (((key[2]=='M' || key[2]=='m') && key[3]=='d') || (key[2]=='T' && key[3]=='g'));
#if defined(__arm64__)
    // Only the firmware fan-control handoff flag; values remain boolean.
    if (strcmp(key, "Ftst") == 0) {
        if (value->type != fourcc("ui8 ") || value->size != 1 || value->bytes[0] > 1) return -3;
        fanKey = 1;
    }
#endif
    if (!fanKey && strcmp(key, "FS! ") != 0) return -3;
    SMCMessage in = {0}, out = {0};
    in.key = fourcc(key); in.command = 6; in.info.size = value->size;
    memcpy(in.bytes, value->bytes, 32);
    return call(connection, &in, &out);
}
static int hexDigit(unsigned char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}
double ts_decode(const TSValue *v) {
    if (!v) return NAN;
    // SMC fixed-point types encode integer/fractional bit counts in hexadecimal.
    unsigned char first=v->type>>24, second=v->type>>16;
    int integer=hexDigit((v->type>>8)&255), fraction=hexDigit(v->type&255);
    if (v->size == 2 && second == 'p' && integer >= 0 && fraction >= 0 &&
        ((first == 's' && integer + fraction == 15) || (first == 'f' && integer + fraction == 16))) {
        uint16_t bits=(uint16_t)((v->bytes[0]<<8)|v->bytes[1]);
        return (first == 's' ? (double)(int16_t)bits : (double)bits) / (double)(1u<<fraction);
    }
    if (v->type == fourcc("flt ") && v->size == 4) {
        float f; memcpy(&f, v->bytes, 4); return f;
    }
    if (v->type == fourcc("ui8 ") && v->size == 1) return v->bytes[0];
    if (v->type == fourcc("ui16") && v->size == 2) return (v->bytes[0]<<8)|v->bytes[1];
    if (v->type == fourcc("ui32") && v->size == 4)
        return (uint32_t)v->bytes[0]<<24 | (uint32_t)v->bytes[1]<<16 | (uint32_t)v->bytes[2]<<8 | v->bytes[3];
    return NAN;
}
int ts_encode(double n, TSValue *v) {
    if (!v || !isfinite(n) || n < 0) return -1;
    if (v->type == fourcc("fpe2") && v->size == 2 && n <= 16383.75) {
        uint16_t x = (uint16_t)lround(n*4); v->bytes[0]=x>>8; v->bytes[1]=x&255; return 0;
    }
    if (v->type == fourcc("flt ") && v->size == 4 && n <= 20000) {
        float f=(float)n; memcpy(v->bytes, &f, 4); return 0;
    }
    if (v->type == fourcc("ui8 ") && v->size == 1 && n <= 255) { v->bytes[0]=(uint8_t)n; return 0; }
    if (v->type == fourcc("ui16") && v->size == 2 && n <= 65535) {
        uint16_t x=(uint16_t)n; v->bytes[0]=x>>8; v->bytes[1]=x&255; return 0;
    }
    return -2;
}
static int dictInt(CFDictionaryRef dict, CFStringRef key) {
    CFTypeRef v=CFDictionaryGetValue(dict, key); int n=-1;
    if (v && CFGetTypeID(v)==CFNumberGetTypeID()) CFNumberGetValue(v, kCFNumberIntType, &n);
    return n;
}
TSPower ts_power_status(void) {
    TSPower p={-1,-1,-1,-1}; CFDictionaryRef dict=NULL;
    if (IOPMCopyCPUPowerStatus(&dict)==kIOReturnSuccess && dict) {
        p.speed=dictInt(dict, CFSTR(kIOPMCPUPowerLimitProcessorSpeedKey));
        p.scheduler=dictInt(dict, CFSTR(kIOPMCPUPowerLimitSchedulerTimeKey));
        p.available=dictInt(dict, CFSTR(kIOPMCPUPowerLimitProcessorCountKey));
        CFRelease(dict);
    }
    uint32_t warning=0;
    if (IOPMGetThermalWarningLevel(&warning)==kIOReturnSuccess) p.warning=(int)warning;
    return p;
}
int ts_cpu_ticks(TSTicks *ticks) {
    host_cpu_load_info_data_t info; mach_msg_type_number_t count=HOST_CPU_LOAD_INFO_COUNT;
    mach_port_t host=mach_host_self();
    kern_return_t r=host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&info, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (r!=KERN_SUCCESS) return (int)r;
    ticks->user=info.cpu_ticks[CPU_STATE_USER]; ticks->system=info.cpu_ticks[CPU_STATE_SYSTEM];
    ticks->idle=info.cpu_ticks[CPU_STATE_IDLE]; ticks->nice=info.cpu_ticks[CPU_STATE_NICE];
    return 0;
}
double ts_continuous_seconds(void) {
    mach_timebase_info_data_t timebase; mach_timebase_info(&timebase);
    return (double)mach_continuous_time()*timebase.numer/timebase.denom/1e9;
}
int ts_owner_alive(int pid, unsigned int uid) {
    struct proc_bsdinfo info={0};
    int size=proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info));
    return size==sizeof(info) && info.pbi_uid==uid;
}
static volatile sig_atomic_t stopRequested=0;
static void stopHandler(int sig) { (void)sig; stopRequested=1; }
void ts_install_stop_handlers(void) {
    signal(SIGTERM, stopHandler); signal(SIGINT, stopHandler); signal(SIGHUP, stopHandler);
}
int ts_should_stop(void) { return stopRequested != 0; }
int ts_turbo_driver_state(void) {
    const void *identifier=CFSTR("com.rugarciap.DisableTurboBoost");
    CFArrayRef ids=CFArrayCreate(NULL, &identifier, 1, &kCFTypeArrayCallBacks);
    CFDictionaryRef dict=KextManagerCopyLoadedKextInfo(ids, NULL);
    CFRelease(ids);
    if (!dict) return -1;
    int loaded=CFDictionaryContainsKey(dict, identifier) ? 1 : 0;
    CFRelease(dict); return loaded;
}
int ts_ac_power(void) {
    CFTypeRef snapshot=IOPSCopyPowerSourcesInfo();
    if (!snapshot) return -1;
    CFStringRef type=IOPSGetProvidingPowerSourceType(snapshot);
    int result=type ? (CFEqual(type, CFSTR(kIOPMACPowerKey)) ? 1 : 0) : -1;
    CFRelease(snapshot); return result;
}

// One native authorization bootstrap per app session; no shell or AppleScript.
#include <Security/Authorization.h>
#include <Security/AuthorizationTags.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
int ts_privileged_session_launch(const char *tool,int owner_pid,unsigned int owner_uid,int *channel_fd) {
    if (!tool || !channel_fd || owner_pid<=1 || owner_uid==0) return -1;
    AuthorizationRef auth=NULL;
    OSStatus result=AuthorizationCreate(NULL,kAuthorizationEmptyEnvironment,kAuthorizationFlagDefaults,&auth);
    if (result!=errAuthorizationSuccess) return (int)result;
    AuthorizationItem item={kAuthorizationRightExecute,strlen(tool),(void*)tool,0};
    AuthorizationRights rights={1,&item};
    result=AuthorizationCopyRights(auth,&rights,kAuthorizationEmptyEnvironment,
        kAuthorizationFlagInteractionAllowed|kAuthorizationFlagExtendRights|kAuthorizationFlagPreAuthorize,NULL);
    if (result==errAuthorizationSuccess) {
        char pid[20],uid[20];snprintf(pid,sizeof(pid),"%d",owner_pid);snprintf(uid,sizeof(uid),"%u",owner_uid);
        char *args[]={"serve",pid,uid,NULL};FILE *channel=NULL;
        result=AuthorizationExecuteWithPrivileges(auth,tool,kAuthorizationFlagDefaults,args,&channel);
        if (result==errAuthorizationSuccess && channel) {
            int fd=dup(fileno(channel));fclose(channel);
            if(fd<0) result=-1;
            else {fcntl(fd,F_SETFD,FD_CLOEXEC);*channel_fd=fd;}
        } else if(result==errAuthorizationSuccess) result=-1;
    }
    AuthorizationFree(auth,kAuthorizationFlagDefaults);
    return (int)result;
}

#include <sys/resource.h>
#include <stdlib.h>
#include <limits.h>
#include <sys/sysctl.h>
int ts_memory_pressure(void) {
    // XNU exports dispatch pressure levels (NORMAL=1, WARN=2, CRITICAL=4).
    // Unsupported/denied sysctl remains unknown, never inferred from RAM usage.
    uint32_t value=0;size_t size=sizeof(value);
    if(sysctlbyname("kern.memorystatus_vm_pressure_level",&value,&size,NULL,0)!=0 || size!=sizeof(value))return -1;
    return value==1 || value==2 || value==4 ? (int)value:-1;
}
int ts_process_snapshot(TSProcessSnapshot *records,int capacity,int *inaccessible) {
    if(!records || capacity<=0) return -1;
    if(inaccessible)*inaccessible=0;
    int needed=proc_listpids(PROC_ALL_PIDS,0,NULL,0);
    if(needed<=0)return -1;
    int bytes=needed+256*(int)sizeof(int);
    int *pids=calloc(1,(size_t)bytes);if(!pids)return -1;
    int actual=proc_listpids(PROC_ALL_PIDS,0,pids,bytes),count=0;
    mach_timebase_info_data_t timebase;mach_timebase_info(&timebase);
    for(int i=0;i<actual/(int)sizeof(int) && count<capacity;i++) {
        int pid=pids[i];if(pid<=0)continue;
        struct rusage_info_v2 usage={0};struct proc_bsdinfo info={0};
        if(proc_pid_rusage(pid,RUSAGE_INFO_V2,(rusage_info_t*)&usage)!=0 ||
           proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&info,sizeof(info))!=(int)sizeof(info)) {
            if(inaccessible)(*inaccessible)++;continue;
        }
        TSProcessSnapshot *p=&records[count++];memset(p,0,sizeof(*p));
        p->pid=pid;p->parent_pid=info.pbi_ppid;p->uid=info.pbi_uid;p->started=usage.ri_proc_start_abstime;
        long double ns=((long double)usage.ri_user_time+usage.ri_system_time)*timebase.numer/timebase.denom;
        p->cpu_ns=ns>ULLONG_MAX ? ULLONG_MAX:(uint64_t)ns;p->memory_bytes=usage.ri_phys_footprint;
        p->disk_read_bytes=usage.ri_diskio_bytesread;p->disk_write_bytes=usage.ri_diskio_byteswritten;
        if(proc_name(pid,p->name,sizeof(p->name))<=0)snprintf(p->name,sizeof(p->name),"%s",info.pbi_comm);
    }
    free(pids);return count;
}
int ts_process_identity(int32_t pid,uint32_t uid,uint64_t started) {
    struct rusage_info_v2 usage={0};struct proc_bsdinfo info={0};
    return proc_pid_rusage(pid,RUSAGE_INFO_V2,(rusage_info_t*)&usage)==0 &&
        proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&info,sizeof(info))==(int)sizeof(info) &&
        info.pbi_uid==uid && usage.ri_proc_start_abstime==started;
}
