#ifndef TS_SMC_H
#define TS_SMC_H
#include <stdint.h>
#include <stddef.h>

typedef struct { uint32_t size; uint32_t type; uint8_t bytes[32]; } TSValue;
typedef struct { int speed; int scheduler; int available; int warning; } TSPower;
typedef struct { uint64_t user; uint64_t system; uint64_t idle; uint64_t nice; } TSTicks;
uint32_t ts_smc_open(void);
void ts_smc_close(uint32_t connection);
int ts_smc_read(uint32_t connection, const char *key, TSValue *value);
int ts_smc_write(uint32_t connection, const char *key, const TSValue *value);
double ts_decode(const TSValue *value);
int ts_encode(double number, TSValue *value);
TSPower ts_power_status(void);
int ts_cpu_ticks(TSTicks *ticks);
double ts_continuous_seconds(void);
int ts_owner_alive(int pid, unsigned int uid);
void ts_install_stop_handlers(void);
int ts_should_stop(void);
int ts_turbo_driver_state(void);
int ts_ac_power(void);
typedef struct {int32_t pid;int32_t parent_pid;uint32_t uid;uint64_t started;uint64_t cpu_ns;uint64_t memory_bytes;uint64_t disk_read_bytes;uint64_t disk_write_bytes;char name[96];} TSProcessSnapshot;
int ts_memory_pressure(void);
int ts_process_snapshot(TSProcessSnapshot *records,int capacity,int *inaccessible);
int ts_process_identity(int32_t pid,uint32_t uid,uint64_t started);
int ts_privileged_session_launch(const char *tool, int owner_pid, unsigned int owner_uid, int *channel_fd);
int ts_smc_key_at_index(uint32_t connection,uint32_t index,char *key);
#endif
