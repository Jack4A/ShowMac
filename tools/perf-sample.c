#include <libproc.h>
#include <sys/resource.h>
#include <time.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
static double now(clockid_t clock){struct timespec t;clock_gettime(clock,&t);return t.tv_sec+t.tv_nsec/1e9;}
int main(int argc,char**argv){
 if(argc!=3){fprintf(stderr,"usage: perf-sample PID SECONDS\n");return 2;}
 int pid=atoi(argv[1]),seconds=atoi(argv[2]);if(pid<=1||seconds<5||seconds>3600)return 2;
 puts("monotonic_s,epoch_s,user_ns,system_ns,footprint_bytes,resident_bytes,pkg_idle_wakeups,interrupt_wakeups,read_bytes,write_bytes,start_id,energy_nj,rusage_version");fflush(stdout);
 uint64_t identity=0;
 for(int i=0;i<=seconds;i++){
  struct rusage_info_v6 r;memset(&r,0,sizeof(r));int version=RUSAGE_INFO_V6;
  if(proc_pid_rusage(pid,version,(rusage_info_t*)&r)!=0){memset(&r,0,sizeof(r));version=RUSAGE_INFO_V4;if(proc_pid_rusage(pid,version,(rusage_info_t*)&r)!=0){fprintf(stderr,"pid read failed: %s\n",strerror(errno));return 3;}}
  if(i==0)identity=r.ri_proc_start_abstime;if(r.ri_proc_start_abstime!=identity){fprintf(stderr,"PID identity changed\n");return 4;}
  printf("%.9f,%.6f,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%d\n",now(CLOCK_MONOTONIC),now(CLOCK_REALTIME),r.ri_user_time,r.ri_system_time,r.ri_phys_footprint,r.ri_resident_size,r.ri_pkg_idle_wkups,r.ri_interrupt_wkups,r.ri_diskio_bytesread,r.ri_diskio_byteswritten,r.ri_proc_start_abstime,version==RUSAGE_INFO_V6?r.ri_energy_nj:0,version);fflush(stdout);
  if(i<seconds){struct timespec delay={1,0};while(nanosleep(&delay,&delay)!=0&&errno==EINTR){}}
 }
 return 0;
}
