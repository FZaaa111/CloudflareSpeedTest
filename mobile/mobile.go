// Package mobile 为 iOS App 提供测速接口，通过 gomobile bind 编译为 iOS framework。
// 导出的类型和函数只使用 gomobile 支持的类型（int、float64、string、bool、error、结构体指针、接口）。
package mobile

import (
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/XIU2/CloudflareSpeedTest/task"
	"github.com/XIU2/CloudflareSpeedTest/utils"
)

// 延迟测速线程上限（与命令行一致）
const maxMobileRoutines = 1000

// Config 测速参数，对应命令行参数
type Config struct {
	Routines        int     // 延迟测速线程 -n
	PingTimes       int     // 延迟测速次数 -t
	Port            int     // 指定测速端口 -tp
	TestURL         string  // 指定测速地址 -url
	Httping         bool    // 切换测速模式 -httping
	HttpingCode     int     // 有效状态代码 -httping-code
	ColoFilter      string  // 匹配指定地区 -cfcolo
	MaxDelay        int     // 平均延迟上限 -tl (ms)
	MinDelay        int     // 平均延迟下限 -tll (ms)
	MaxLossRate     float64 // 丢包几率上限 -tlr
	MinSpeed        float64 // 下载速度下限 -sl (MB/s)
	DownloadCount   int     // 下载测速数量 -dn
	DownloadSeconds int     // 下载测速时间 -dt (秒)
	DisableDownload bool    // 禁用下载测速 -dd
	TestAll         bool    // 测速全部的IP -allip
	IPRanges        string  // IP 段数据，逗号或换行分隔 -ip
	Debug           bool    // 调试输出模式 -debug
}

// NewConfig 返回带默认值的测速参数（与命令行默认值一致）
func NewConfig() *Config {
	return &Config{
		Routines:        200,
		PingTimes:       4,
		Port:            443,
		TestURL:         "https://cf.xiu2.xyz/url",
		MaxDelay:        9999,
		MinDelay:        0,
		MaxLossRate:     1,
		DownloadCount:   10,
		DownloadSeconds: 10,
	}
}

// Listener 测速进度回调，由 Swift 端实现
type Listener interface {
	// OnProgress stage 为 ping（延迟测速）或 download（下载测速）
	OnProgress(stage string, done, total int)
	OnLog(msg string)
}

// Result 单个 IP 的测速结果（JSON 输出）
type Result struct {
	IP        string  `json:"ip"`
	Sent      int     `json:"sent"`
	Received  int     `json:"received"`
	LossRate  float64 `json:"lossRate"`
	DelayMs   float64 `json:"delayMs"`
	SpeedMBps float64 `json:"speedMBps"`
	Colo      string  `json:"colo"`
}

var runLock sync.Mutex // 测速核心使用全局变量，同一时间只允许一个测速任务

// Run 执行测速（阻塞），返回按速度（禁用下载测速时按延迟）排序的结果 JSON 数组
func Run(cfg *Config, l Listener) (string, error) {
	if cfg == nil {
		cfg = NewConfig()
	}
	if !runLock.TryLock() {
		return "", errors.New("已有测速任务正在进行")
	}
	defer runLock.Unlock()

	ipText := strings.Join(strings.FieldsFunc(cfg.IPRanges, func(r rune) bool {
		return r == ',' || r == '\n' || r == '\r'
	}), ",")
	if strings.TrimSpace(ipText) == "" {
		return "", errors.New("IP 段数据为空")
	}

	raiseFileLimit()
	applyConfig(cfg, ipText)
	task.ResetCancel()
	task.InitRandSeed()

	logf := func(msg string) {
		if l != nil {
			l.OnLog(msg)
		}
	}
	if l != nil {
		utils.ProgressHook = l.OnProgress
		defer func() { utils.ProgressHook = nil }()
	}

	logf("开始延迟测速")
	pingData := task.NewPing().Run().FilterDelay().FilterLossRate()
	if task.IsCanceled() {
		logf("测速已取消")
	} else {
		logf("延迟测速完成，可用 IP 数量：" + strconv.Itoa(len(pingData)))
	}
	if !cfg.DisableDownload && !task.IsCanceled() {
		logf("开始下载测速")
	}
	speedData := task.TestDownloadSpeed(pingData)
	logf("测速完成，结果数量：" + strconv.Itoa(len(speedData)))

	results := make([]Result, 0, len(speedData))
	for i := range speedData {
		d := &speedData[i]
		results = append(results, Result{
			IP:        d.IP.String(),
			Sent:      d.Sended,
			Received:  d.Received,
			LossRate:  float64(d.LossRate()),
			DelayMs:   float64(d.Delay) / float64(time.Millisecond),
			SpeedMBps: d.DownloadSpeed / 1024 / 1024,
			Colo:      d.Colo,
		})
	}
	b, err := json.Marshal(results)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// Stop 取消正在进行的测速，Run 会尽快返回已完成部分的结果
func Stop() {
	task.Cancel()
}

func applyConfig(cfg *Config, ipText string) {
	utils.Quiet = true
	utils.Output = "" // 不写入 CSV 文件
	utils.PrintNum = 0
	utils.Debug = cfg.Debug

	task.StrictIP = false // 跳过无法解析的 IP 段，避免 App 退出
	task.IPText = ipText
	task.TestAll = cfg.TestAll

	task.Routines = cfg.Routines
	if task.Routines > maxMobileRoutines {
		task.Routines = maxMobileRoutines
	}
	task.PingTimes = cfg.PingTimes
	task.TCPPort = cfg.Port
	task.URL = cfg.TestURL
	task.Httping = cfg.Httping
	task.HttpingStatusCode = cfg.HttpingCode
	task.HttpingCFColo = cfg.ColoFilter
	task.HttpingCFColomap = task.MapColoMap()

	task.TestCount = cfg.DownloadCount
	task.Timeout = time.Duration(cfg.DownloadSeconds) * time.Second
	task.Disable = cfg.DisableDownload
	task.MinSpeed = cfg.MinSpeed

	maxDelay := cfg.MaxDelay
	if maxDelay <= 0 {
		maxDelay = 9999
	}
	maxLoss := cfg.MaxLossRate
	if maxLoss <= 0 || maxLoss > 1 {
		maxLoss = 1
	}
	utils.InputMaxDelay = time.Duration(maxDelay) * time.Millisecond
	utils.InputMinDelay = time.Duration(cfg.MinDelay) * time.Millisecond
	utils.InputMaxLossRate = float32(maxLoss)
}
