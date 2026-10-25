# 星砂 Stardust

macOS 上的一个引力沙盘。三千颗粒子在引力场里绕行，拖出光带。

不是录好的动画，是每帧现算的 N 体模拟。

## 下载

到 [Releases](../../releases) 页面下载最新版 **Stardust-1.0.zip**，解压后把
`Stardust.app` 拖进「应用程序」文件夹。

首次启动 macOS 会拦截（个人开发者没有 $99/年的 Apple 公证）：右键点
app 图标 →「打开」→ 在弹窗里再点一次「打开」即可，之后照常启动。
也可以终端里跑一次 `xattr -cr /Applications/Stardust.app` 永久放行。

- 系统要求：macOS 14.0+，**Apple Silicon**（M 系列芯片）

## 玩法

- **按住鼠标**：出现一个引力源，把粒子吸过来；按得越久引力越强，松手后粒子被甩出去
- **按住 Option 再拖**：变成排斥力，把粒子推开
- **双击**：超新星爆发，粒子从爆点向外炸开，画面会抖一下
- **顶部控制条**：切换配色、粒子数、引力强度、暂停、重置。停手 2.4 秒自动淡出，动一下鼠标就回来
- 四套配色：极光 / 熔岩 / 深海 / 素白

## 它是怎么动的

- 3000 个粒子，每个都受主星、伴星（按住鼠标时再加上鼠标引力源）的平方反比引力
- 初始位置按圆轨道给速度，所以一开机就是个稳定的盘
- 落进核心的粒子会被"回收"到外圈重新开始，盘不会塌
- 伴星以 r=0.19 绕主星公转，不断轻微扰动，盘面因此一直有变化

拖尾不是残影，是每颗粒子存两个滞后锚点，连起来画两段折线：

```
远锚点  ──────  近锚点  ───  当前位置
（tau=0.115/v）      （tau=0.035/v）
```

时间常数和速度成反比，所以**每颗粒子的尾巴长度是一样的**。这一条很关键——
如果时间常数固定，中心高速粒子的尾巴会长出好几倍，几千条叠在一起就是一团白。

## 性能

600 帧物理 0.03 秒，平均 0.05 ms/帧。瓶颈全在绘制（每帧 32 次描边：8 档速度 × 2 段 × 2 层辉光）。

## 踩过的坑

1. **`@State` 编译不过**。Command Line Tools 没带 SwiftUIMacros 插件，
   报 `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found`。
   `@StateObject` 还是老的 propertyWrapper，能用，所以把 UI 的零碎状态都塞进一个 `UIState`。
2. **拖尾完全没有**。`step()` 开头残留了一行 `p.nx = p.x; p.fx = p.y`——那是早先记录上一帧位置留下的，
   结果每帧都把锚点重置到当前位置，尾巴长度永远是零。删掉就好了。
3. **中心糊成一团白**。粒子面密度 ∝ 1/r，中心本来就密；再加上当时"越快的粒子线越粗"，
   两个因素叠起来就是过曝。改成快粒子用细线、中心挖空交给核球辉光。
4. **整个盘炸开过一次**。伴星质量 0.055 在 r=0.245 公转，正好穿过粒子环带，
   近距离掠过把粒子加速到速度上限，然后满屏乱飞。降到 0.016、轨道收到 0.19、
   软核从 0.0006 放到 0.0016 才稳住。
5. **悬停显示控制条不生效**。`onContinuousHover` 挂在了 `opacity: 0` 的视图上，
   收不到事件，于是永远显示不出来。改用 `NSEvent.addLocalMonitorForEvents` 监听鼠标移动，
   配合 2.4 秒定时淡出。

## 自检

```bash
./Stardust --bench
```

跑 600 帧，打印物理耗时、平均/最大速度、到中心的半径直方图（每 0.09 一档）。

改完参数先看这个。**半径直方图如果跑到第 7、8 档（半径 > 0.72），说明盘散了**，
大概率是伴星质量或速度上限给大了。

正常状态长这样：

```
粒子 3000，平均速度 0.2007，最大 0.3390
半径直方图(每 0.09):    1  777  973  703  471   75    0    0
最远半径 0.508
```

## 文件

| 文件 | 说明 |
|---|---|
| `main.swift` | 全部代码，模拟 + 界面 |
| `makeicon.swift` | 程序化生成图标（旋涡星系，无位图素材） |
| `Stardust.app` | 可直接运行，adhoc 签名 |
| `Stardust-1.0.zip` | 分发包 |
| `screenshot-*.png` | 截图 |

## 自己编译

```bash
SDK=$(xcrun --show-sdk-path)
swiftc -sdk "$SDK" -target arm64-apple-macos14.0 -parse-as-library -O main.swift -o Stardust
```

`-parse-as-library` 不能少，否则 `@main` 会报 "cannot be used in a module that contains top-level code"。

重画图标：

```bash
swiftc -O makeicon.swift -o makeicon && ./makeicon && iconutil -c icns Stardust.iconset -o Stardust.icns
```
