//go:build !windows && !plan9 && !js && !wasip1

package mobile

import "syscall"

// raiseFileLimit 提高进程可打开文件数上限（iOS 默认软限制为 256），避免高并发延迟测速时连接失败
func raiseFileLimit() {
	var rl syscall.Rlimit
	if err := syscall.Getrlimit(syscall.RLIMIT_NOFILE, &rl); err != nil {
		return
	}
	target := rl.Max
	if target > 4096 {
		target = 4096
	}
	if rl.Cur < target {
		rl.Cur = target
		_ = syscall.Setrlimit(syscall.RLIMIT_NOFILE, &rl)
	}
}
