import Foundation
import Darwin
import ThermalCore

/// Only installed while sleep is overridden. launchd restores sleep at the next
/// boot if both the app and its independent watchdog were forcibly killed.
/// Use an OS shell for this fixed recovery action so it also works on macOS 11
/// without the app bundle's Swift compatibility libraries. No user text enters it.
enum ClamshellRecovery {
    static let script="/Library/PrivilegedHelperTools/cc.showmac.clamshell-recovery"
    static let job="/Library/LaunchDaemons/cc.showmac.clamshell-recovery.plist"
    static var isPrepared:Bool {
        var info=stat()
        return lstat(job,&info)==0 && info.st_uid==0 && info.st_mode & S_IFMT == S_IFREG && info.st_mode & 0o077==0
    }
    static let body="""
    #!/bin/sh
    set -eu
    /usr/bin/pmset -a disablesleep 0
    if ! /usr/sbin/ioreg -r -c IOPMrootDomain -d 1 | /usr/bin/grep -q '\"SleepDisabled\" = No'; then
        exit 1
    fi
    /bin/rm -f /Library/LaunchDaemons/cc.showmac.clamshell-recovery.plist
    /bin/rm -f /Library/PrivilegedHelperTools/cc.showmac.clamshell-recovery
    """+"\n"
    static func prepare() throws {
        guard geteuid()==0 else {throw ScopeError.message("合盖运行需要系统授权")}
        for directory in ["/Library/PrivilegedHelperTools","/Library/LaunchDaemons"] {
            if access(directory,F_OK) != 0 {guard mkdir(directory,0o755)==0 else {throw ScopeError.message("无法建立合盖运行恢复保护")}}
            var info=stat()
            guard lstat(directory,&info)==0,info.st_mode & S_IFMT == S_IFDIR,info.st_uid==0,info.st_mode & 0o022==0 else {
                throw ScopeError.message("无法建立合盖运行恢复保护")
            }
        }
        let configuration:[String:Any]=[
            "Label":"cc.showmac.clamshell-recovery",
            "ProgramArguments":["/bin/sh",script],
            "RunAtLoad":true,"KeepAlive":["SuccessfulExit":false],"ThrottleInterval":10
        ]
        try write(Data(body.utf8),to:script,mode:0o700)
        try write(PropertyListSerialization.data(fromPropertyList:configuration,format:.xml,options:0),to:job,mode:0o600)
    }
    static func clear() throws {
        // Remove the job before its target. A crash at either step cannot leave
        // a boot job pointing to a missing executable while sleep is disabled.
        for path in [job,script] {
            var info=stat()
            if lstat(path,&info) != 0 {if errno==ENOENT {continue};throw ScopeError.message("无法移除合盖运行恢复保护")}
            guard info.st_uid==0,info.st_mode & S_IFMT == S_IFREG,unlink(path)==0 else {throw ScopeError.message("无法移除合盖运行恢复保护")}
        }
    }
    private static func write(_ data:Data,to path:String,mode:mode_t) throws {
        var template=Array((path+".XXXXXX").utf8CString)
        let fd=mkstemp(&template)
        guard fd>=0 else {throw ScopeError.message("无法建立合盖运行恢复保护")}
        let temporary=String(cString:template)
        defer {close(fd);unlink(temporary)}
        guard fchmod(fd,mode)==0,fchown(fd,0,0)==0 else {throw ScopeError.message("无法建立合盖运行恢复保护")}
        try data.withUnsafeBytes {buffer in
            var offset=0
            while offset<buffer.count {
                let count=Darwin.write(fd,buffer.baseAddress!.advanced(by:offset),buffer.count-offset)
                if count<0,errno==EINTR {continue}
                guard count>0 else {throw ScopeError.message("无法建立合盖运行恢复保护")}
                offset+=count
            }
        }
        guard fsync(fd)==0,rename(temporary,path)==0 else {throw ScopeError.message("无法建立合盖运行恢复保护")}
        let directory=open((path as NSString).deletingLastPathComponent,O_RDONLY|O_DIRECTORY)
        if directory>=0 {
            defer{close(directory)}
            if fsync(directory) != 0,errno != EINVAL {throw ScopeError.message("无法建立合盖运行恢复保护")}
        }
    }
}
