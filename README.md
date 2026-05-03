
**版本：** V4.3 (2026-05-03)
**适用环境：** Cadence IC23.1+ (Virtuoso Explorer/Maestro)
**主要功能：** 一键导出仿真列表信号，并自动调用 Python 脚本生成 Spectre 格式的电流保存网表 (`.scs`)。
## 系统要求
- **Cadence 环境：** 需支持 ADE Explorer (底层识别名需包含 `explorer` 或 `maestro`)。
- **Python 环境：** 系统需安装 Python 3.x，并确保 `python3` 命令在环境变量中。
- **权限要求：** 用户需对 Python 脚本路径及工作目录具有读写权限。
- 适用范围：C+CC、C、No RC这几种工况是确定能用的，R+C+CC是理论上来说可以使用，但是没有经过测试
## 工作原理
传统的后仿保存电流的流程较为复杂，一般而言是先开启save all并运行一个时间很短（比如1ps）的仿真，以确定要保存的电流名称，之后将名称复制到一个独立的scs当中，并重新将scs文件加回到仿真文件的definition里；最后运行仿真，自动保存对应的电流波形。这个流程可行但是非常的复杂，核心点在于难以快速而准确的从大量的电流当中获取需要的电流。
然而，通过观察可以发现，其实后仿的器件命名是存在一定规律的，因此可以通过这种方式直接从前仿保存的电流当中推导出后仿需要保存电流的名字，并将其写入到scs文件当中。
这个小工具的主要就是将这个流程自动化，并提供了一个GUI。
基本流程分为四步：
	1. 从ADE Explorer的Output Setup当中导出结果到CSV
	2. 解析CSV文件当中的保存项，找到深层电流信号
	3. 将深层电流信号按照规则转换为对应的save指令
	4. 将save指令生成为scs文件
最后，将scs文件加载到`Simulation File`里的`Definition Files`当中，并运行仿真。最后在`Result Browser`当中查看结果
## 文件结构与安装
### 文件存放
文件可以直接从github下载，路径为 https://github.com/OliverKung/Post-Simulation-Current-Probe ，如果你对于git的使用比较熟悉也可以直接用git下载到本地。
建议将工具存放于以下目录（或您的自定义脚本路径）：
- **SKILL 脚本：** `~/scripts/current_save_converter.il`
- **Python 脚本：** `~/scripts/pss_scsg_file.py`
### 路径配置
在正式运行前，请打开 `current_save_converter.il` 文件，确认以下变量指向正确的 Python 脚本位置：
```Lisp
pyScript = "~/scripts/pss_scsg_file.py"  ;; 请确保此路径为绝对路径或正确的主目录缩写
```
### 自动加载设置
为了在启动 Virtuoso 时自动加载该工具，请在您的 `~/.cdsinit` 文件末尾添加以下代码：
```Lisp
if( isFile(simplifyFilename("~/scripts/current_save_converter.il")) then
    load(simplifyFilename("~/scripts/current_save_converter.il"))
)
```
## 使用步骤
### 确认安装正常
观察Virtuoso启动之后的窗口（这个窗口学名为CIW），如果出现如下图的字样则说明加载成功，如果没有请返回上一步检查是否配置错误。
![[Pasted image 20260503164733.png]]
### 启动工具
1. 打开您的 **ADE Explorer** 窗口。
2. 在顶部菜单栏最右侧找到 **[PostSim]** 菜单。
3. 点击 **Generate Current Probe**。
![[Pasted image 20260503170857.png]]
### 配置输入输出路径
工具会弹出一个设置对话框：
- **Input CSV Path:** 填入您打算导出的信号列表文件名（默认路径为 `/tmp/ade_signals_export.csv`）。
- **Output SCS Path:** 填入转换后生成的 `.scs` 文件路径（默认在当前工程目录下）。
- 点击 **OK** 确认。
    ![[Pasted image 20260503170928.png]]

### 确认原生导出对话框
这里因为Virtuoso提供的API太蠢了，因此需要二次确认一次，直接选中对应的csv或者在下面输入文件名都可以。
![[Pasted image 20260503171150.png]]
### 查看转换结果
1. 保存完成后，后台会运行 Python 转换引擎。
2. 运行结束后会弹出 **Parser Result (V4.3)** 对话框，显示：
    - 生成的 `.scs` 文件路径。
    - Python 运行日志摘要（包括处理的信号数量等）。
![[Pasted image 20260503171226.png]]
## 仿真集成
生成的 `.scs` 文件包含了 Spectre 的 `save` 指令。您可以直接在 ADE Explorer 中将其添加为定义文件：
- `Setup -> Model Libraries -> Add File`
- 或者在仿真网表中 `include` 该文件。
- 或者直接`Definition Files`里加入这个文件
## 关于配置
默认的配置文件是基于华虹的180BCD工艺设置的，一定不会通用与所有的工艺，各位可能需要手动调整下匹配关系。
```python
PDK_CONFIG_A = {
    "prefix_map": {
        "I": "XI",   
        "M": "MM",   
        "LD": "MM",  
        "R": "RR",   
        "C": "CC"    
    },
    "special_map": {
    },
    "multi_finger": {
        "enable": True,
        "target_prefixes": ["M", "LD"], 
        "wildcard": "*" 
    },
    "hierarchy_sep": "\\/",        
    "subckt_suffix": ".mxckt",     
    "terminal_case": "lower"       
}
```
分为五个部分，分别是前缀映射、特殊映射、多finger映射、层级分隔以及后缀。
前缀映射就是器件到后仿之后的前缀会变成什么，根据不同的工艺稍微对比下应该就能看出来了。
特殊映射顾名思义，对于一些不符合转换规则或者映射比较费劲的，可以在这里使用特殊映射专门制定一个转换关系。
多finger映射则是对于一些带有并联的器件，脚本会利用通配符自动保存所有的finger的电流。
层级分隔和后缀，顾名思义，有的可能会使用`.`而不是`/`来分隔层级，因此在这里有一个设置，后缀的话是因为有的建模是一个小的subcircuit，不能直接接器件的端子。
