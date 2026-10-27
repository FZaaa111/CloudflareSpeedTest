package utils

import (
	"fmt"

	"github.com/cheggaaa/pb/v3"
)

var (
	// Quiet 为 true 时不在终端渲染进度条（如嵌入 iOS App 时）
	Quiet = false
	// ProgressHook 进度回调（可选），stage 为当前阶段（ping / download），done 为已完成数量，total 为总数
	ProgressHook func(stage string, done, total int)
)

type Bar struct {
	pb    *pb.ProgressBar
	stage string
	done  int
	total int
}

func NewBar(count int, MyStrStart, MyStrEnd string) *Bar {
	b := &Bar{total: count}
	if !Quiet {
		tmpl := fmt.Sprintf(`{{counters . }} {{ bar . "[" "-" (cycle . "↖" "↗" "↘" "↙" ) "_" "]"}} %s {{string . "MyStr" | green}} %s `, MyStrStart, MyStrEnd)
		b.pb = pb.ProgressBarTemplate(tmpl).Start(count)
	}
	return b
}

// WithStage 设置进度回调中使用的阶段名称
func (b *Bar) WithStage(stage string) *Bar {
	b.stage = stage
	if ProgressHook != nil {
		ProgressHook(b.stage, 0, b.total)
	}
	return b
}

func (b *Bar) Grow(num int, MyStrVal string) {
	b.done += num
	if b.pb != nil {
		b.pb.Set("MyStr", MyStrVal).Add(num)
	}
	if ProgressHook != nil {
		ProgressHook(b.stage, b.done, b.total)
	}
}

func (b *Bar) Done() {
	if b.pb != nil {
		b.pb.Finish()
	}
}
