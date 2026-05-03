# -*- coding: utf-8 -*-
import argparse
import csv
import os
import sys

# ==========================================
# 1. 工艺配置区 (Rule Configurations)
# ==========================================

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


# ==========================================
# 2. 核心转换引擎 (Core Engine)
# ==========================================

def apply_pdk_rules(raw_signal, config):
    """根据传入的 PDK 配置文件，解析并转换信号路径"""
    # 清理多余的引号和斜杠
    raw_signal = raw_signal.strip().strip('"').strip("'").strip('/')
    parts = raw_signal.split('/')
    
    # 如果层级少于3层 (例如 /I36/Co)，说明是模块顶层引脚，而非深层物理器件，直接跳过
    if len(parts) < 3:
        return None, None
        
    top_level = parts[0]
    terminal = parts[-1]
    middle_devices = parts[1:-1]
    
    if config["terminal_case"] == "lower":
        terminal = terminal.lower()
    elif config["terminal_case"] == "upper":
        terminal = terminal.upper()

    converted_devices = []
    
    for i, item in enumerate(middle_devices):
        new_item = item 
        is_leaf_device = (i == len(middle_devices) - 1)
        
        # 1. 检查特殊映射
        if item in config.get("special_map", {}):
            new_item = config["special_map"][item]
        else:
            # 2. 检查前缀映射
            first_char = item[0] if item else ""
            prefix_match = next((p for p in config["prefix_map"].keys() if item.startswith(p)), None)
            
            if prefix_match:
                new_item = config["prefix_map"][prefix_match] + item[len(prefix_match):]
        
        # 3. 多指打散器件处理 (注入通配符)
        if is_leaf_device and config.get("multi_finger", {}).get("enable"):
            targets = config["multi_finger"].get("target_prefixes", [])
            if any(item.startswith(p) for p in targets):
                new_item += config["multi_finger"].get("wildcard", "*")
                
        converted_devices.append(new_item)
            
    # 组装最终路径
    device_path = "X"+config["hierarchy_sep"].join(converted_devices)
    scs_command = f"save \"{top_level}.{device_path}{config['subckt_suffix']}:{terminal}\""
    
    # ADE Calculator 求和表达式
    ocean_path = f"{top_level}.{device_path}{config['subckt_suffix']}:{terminal}".replace("\\/", "\\\\/")
    ocean_expr = f'sum(getData("{ocean_path}" ?result "tran"))'
    
    return scs_command, ocean_expr


# ==========================================
# 3. CSV 文件 I/O 与判断逻辑
# ==========================================

def process_ade_csv(input_csv, output_scs, config):
    """读取 CSV，判断电流类型，并输出 .scs 文件"""
    
    if not os.path.exists(input_csv):
        print(f"❌ 错误：找不到输入文件 '{input_csv}'")
        sys.exit(1)

    saved_commands = set()
    calculator_exprs = set() # 收集对应的 ADE 计算器表达式
    
    print(f"🔍 正在解析文件: {input_csv} ...")

    with open(input_csv, mode='r', encoding='utf-8-sig') as f:
        # 使用 csv 模块进行结构化读取，自动处理如 "/SUM<8:0>" 中的逗号和引号问题
        reader = csv.reader(f)
        headers = next(reader, None)
        
        if not headers:
            print("❌ 错误：CSV 文件为空")
            sys.exit(1)
            
        try:
            # 动态寻找列的索引，防止 ADE 导出时列顺序变化
            type_idx = headers.index("Type")
            output_idx = headers.index("Output")
        except ValueError:
            print(f"❌ 错误：CSV 表头缺少 'Type' 或 'Output' 列。当前表头: {headers}")
            sys.exit(1)

        current_count = 0
        converted_count = 0

        for row in reader:
            if len(row) <= max(type_idx, output_idx):
                continue
                
            signal_type = row[type_idx].strip().lower()
            signal_path = row[output_idx].strip()

            # 核心判断逻辑：只有 Type == 'terminal' 才是电流
            if signal_type == "terminal":
                current_count += 1
                
                # 开始转换
                scs_cmd, ocean_expr = apply_pdk_rules(signal_path, config)
                
                if scs_cmd:
                    saved_commands.add(scs_cmd)
                    calculator_exprs.add(f"// {signal_path} ->\n// {ocean_expr}")
                    converted_count += 1

    # 写入输出文件
    try:
        with open(output_scs, mode='w', encoding='utf-8') as f:
            f.write("// ===============================================\n")
            f.write("// 自动生成的后仿电流 Save 文件\n")
            f.write(f"// 原始输入文件: {os.path.basename(input_csv)}\n")
            f.write("// ===============================================\n\n")
            
            for cmd in sorted(saved_commands):
                f.write(cmd + "\n")
                
            # 将 ADE 表达式附在文件末尾注释中，方便查阅
            f.write("\n\n// ===============================================\n")
            f.write("// 附录: 用于 ADE Calculator 获取总电流的表达式 \n")
            f.write("// ===============================================\n")
            for expr in sorted(calculator_exprs):
                f.write(expr + "\n")
                
        print(f"✅ 转换完成！")
        print(f"📊 统计信息: 识别到 {current_count} 个电流信号，成功转换了 {converted_count} 个深层器件电流。")
        print(f"📁 结果已保存至: {os.path.abspath(output_scs)}")
        
    except IOError as e:
        print(f"❌ 写入文件失败: {e}")


# ==========================================
# 4. 命令行接口 (CLI)
# ==========================================

if __name__ == "__main__":
    # 配置命令行参数解析器
    parser = argparse.ArgumentParser(
        description="ADE Explorer 导出 CSV 转 后仿 Save Current 脚本",
        formatter_class=argparse.RawTextHelpFormatter
    )
    
    # 添加必要的参数: -i (输入) 和 -o (输出)
    parser.add_argument("-i", "--input", required=True, help="输入的 ADE Maestro 导出 CSV 文件路径 (例如: outputs.csv)")
    parser.add_argument("-o", "--output", default="save_current.scs", help="输出的 SCS 探针文件路径 (默认: save_current.scs)")
    
    # 解析用户输入的参数
    args = parser.parse_args()
    
    # 运行主程序 (此处使用默认的 PDK_CONFIG_A)
    process_ade_csv(input_csv=args.input, output_scs=args.output, config=PDK_CONFIG_A)
