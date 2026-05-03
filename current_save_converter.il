;; ======================================================================
;; Script: auto_save_current.il
;; Version: 4.3 (Auto-Fill Fixed & Version Tagged)
;; Description: Post-Sim Current Parser with Interactive Setup Window
;; ======================================================================

;; ----------------------------------------------------------------------
;; 1. 核心执行逻辑 (包含目录劫持与异步字符注入)
;; ----------------------------------------------------------------------
procedure( RunCurrentParserFromForm( form )
    let( (csvFile scsFile pyScript logFile cmd inPort line logText msgBoxText targetDir fileName oldDir timerCmd parts)
        
        ;; ---------------------------------------------------------
        ;; ★ 打印版本号标识 (满足需求)
        ;; ---------------------------------------------------------
        printf("\n==================================================\n")
        printf("▶ Running Post-Sim Current Parser [Version: 4.3]\n")
        printf("==================================================\n")
        
        ;; 从弹出的表单中读取用户填写的路径
        csvFile = form->csvPathField->value
        scsFile = form->scsPathField->value
        
        ;; Python 脚本的绝对路径 (请确保此路径正确)
        pyScript = "~/skill_scripts/pss_scsg_file.py"   
        logFile  = "/tmp/ade_parser_log.txt"

        ;; =========================================================
        ;; 对话框路径与名称全自动同步逻辑
        ;; =========================================================
        ;; 1. 剥离目录
        rexCompile("[^/]+$")
        targetDir = rexReplace(csvFile "" 1)
        if( targetDir == "" then targetDir = getWorkingDir() )
        
        ;; 2. 剥离文件名 (修复 fileTail 报错，改用最原生的 parseString)
        parts = parseString(csvFile "/")
        if( parts then
            fileName = car(last(parts))
        else
            fileName = "export.csv"
        )
        
        oldDir = getWorkingDir()
        
        printf("Syncing export dialog path to: %s\n" targetDir)
        printf("Auto-filling export file name: %s\n" fileName)
        
        ;; 3. 瞬间切换底层工作目录到目标文件夹
        errset( changeWorkingDir(targetDir) )
        
        if( isCallable('sevExportOutputsToCSV) && hiGetCurrentWindow() then
            printf("Waiting for user to confirm the Export Dialog...\n")
            ;; 5. 呼出系统原生导出对话框
            sevExportOutputsToCSV(sevSession(hiGetCurrentWindow()))
            
            ;; 4. 异步定时器黑科技：延迟 300 毫秒 (3个单位) 后强制执行填表动作
            timerCmd = sprintf(nil "
                let((frm)
                    frm = hiGetCurrentForm()
                    if(frm then
                        errset(frm->file->value = \"%s\")
                        errset(frm->fileName->value = \"%s\")
                        errset(frm->exportFile->value = \"%s\")
                        errset(frm->name->value = \"%s\")
                    )
                )
            " fileName fileName fileName fileName)
            
            hiRegTimer(timerCmd 3)
            

        else
            printf("⚠️ Error: sevExportOutputsToCSV is not available in this window.\n")
        )
        
        ;; 6. 对话框点完 Save 后，立刻把系统工作目录恢复原状
        errset( changeWorkingDir(oldDir) )
        ;; =========================================================

        ;; 确认导出完成后，开始调用 Python 引擎进行正则抓取与转换
        cmd = sprintf(nil "python3 %s -i %s -o %s > %s 2>&1" pyScript csvFile scsFile logFile)
        printf("\nExecuting system command: %s\n" cmd)
        system(cmd)

        ;; 读取日志结果
        logText = ""
        if( isFile(logFile) then
            inPort = infile(logFile)
            while( gets(line inPort) logText = strcat(logText line) )
            close(inPort)
        else
            logText = "Error: Python execution failed. Check terminal/log file."
        )

        ;; 组装并弹出成功提示框
        msgBoxText = strcat("[ Conversion Complete ]\n\nOutput: " scsFile "\n\n--- Log Summary ---\n" logText)
        hiDisplayAppDBox(
            ?name           'AutoParseMsgBox
            ?dboxBanner     "Parser Result (V4.3)"
            ?dboxText       msgBoxText
            ?buttonLayout   'Close
        )
        printf("--- Execution Finished ---\n\n")
    )
)

;; ----------------------------------------------------------------------
;; 2. 创建并显示交互式设置面板 (GUI Form)
;; ----------------------------------------------------------------------
procedure( LaunchPostSimTool()
    let( (csvField scsField)
        
        if( !boundp('PostSimSetupForm) || !PostSimSetupForm then
            
            csvField = hiCreateStringField(
                ?name       'csvPathField
                ?prompt     "Input CSV Path:"
                ?value      "/tmp/ade_signals_export.csv"
                ?defValue   "/tmp/ade_signals_export.csv"
            )
            
            scsField = hiCreateStringField(
                ?name       'scsPathField
                ?prompt     "Output SCS Path:"
                ?value      strcat(getWorkingDir() "/save_current.scs")
                ?defValue   strcat(getWorkingDir() "/save_current.scs")
            )
            
            PostSimSetupForm = hiCreateAppForm(
                ?name           'PostSimSetupForm
                ?formTitle      "Post-Sim Current Save Setup (V4.3)"
                ?fields         list(
                                    list(csvField 10:10 450:30 120)
                                    list(scsField 10:50 450:30 120)
                                )
                ?callback       "RunCurrentParserFromForm( hiGetCurrentForm() )"
                ?buttonLayout   'OKCancel
            )
        )
        hiDisplayForm(PostSimSetupForm)
    )
)

;; ----------------------------------------------------------------------
;; 3. 菜单注册 (纯净版)
;; ----------------------------------------------------------------------
procedure( MyCustomPostInstallTrigger(args)
    let( (win item menu currentMenus)
        win = args->window
        if( win then
            currentMenus = hiGetBannerMenus(win)
            if( !member('MyPostSimMenu currentMenus) then
                item = hiCreateMenuItem(
                    ?name       'AutoParseCurrentItem
                    ?itemText   "Generate Current Probe"
                    ?callback   "LaunchPostSimTool()"
                )
                if( !boundp('MyPostSimMenu) || !MyPostSimMenu then
                    menu = hiCreatePulldownMenu( 'MyPostSimMenu "PostSim" list(item) )
                )
                hiInsertBannerMenu(win 'MyPostSimMenu hiGetNumMenus(win))
            )
        )
    )
)

deUnRegUserTriggers("maestro")
deUnRegUserTriggers("explorer")

deRegUserTriggers("maestro" nil nil 'MyCustomPostInstallTrigger)
deRegUserTriggers("explorer" nil nil 'MyCustomPostInstallTrigger)

printf("\n>>> ================================================== <<<\n")
printf(">>> ===========Post-Sim Helper V4.3 Loaded============ <<<\n")
printf(">>> [Usage]: Click 'PostSim' menu in Explorer window.  <<<\n")
printf(">>> ================================================== <<<\n")
