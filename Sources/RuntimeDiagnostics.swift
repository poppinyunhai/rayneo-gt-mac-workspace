import Foundation
import Darwin

final class RuntimeDiagnostics {
    var lastError=""
    private var lastTime=ProcessInfo.processInfo.systemUptime
    private var lastCPU=0.0
    func sample() -> [String:Any] {
        var usage=rusage();getrusage(RUSAGE_SELF,&usage)
        let cpu=Double(usage.ru_utime.tv_sec+usage.ru_stime.tv_sec)+Double(usage.ru_utime.tv_usec+usage.ru_stime.tv_usec)/1_000_000
        let now=ProcessInfo.processInfo.systemUptime
        let percent=lastCPU>0 ? max(0,(cpu-lastCPU)/max(0.001,now-lastTime)*100) : 0
        lastCPU=cpu;lastTime=now
        var info=mach_task_basic_info()
        var count=mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size/MemoryLayout<natural_t>.size)
        let result=withUnsafeMutablePointer(to:&info) { pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)) {
                task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&count)
            }
        }
        return ["cpuPercent":percent,"residentMB":result==KERN_SUCCESS ? Double(info.resident_size)/1048576 : 0,
                "uptimeSeconds":now,"diagnosticError":lastError]
    }
}
