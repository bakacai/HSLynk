!include "MUI2.nsh"

Name "HSLynk"
OutFile "HSLynk-setup.exe"
InstallDir "$PROGRAMFILES64\HSLynk"

!define SOURCE_DIR "build\windows\x64\runner\Release"

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "SimpChinese"

Section "HSLynk" SecMain
  SetOutPath "$INSTDIR"
  
  # 验证源目录
  IfFileExists "${SOURCE_DIR}\*.*" 0 +3
    File /r "${SOURCE_DIR}\*.*"
    Goto +2
  MessageBox MB_OK|MB_ICONEXCLAMATION "源文件目录不存在：${SOURCE_DIR}"
  Abort
  
  # 创建开始菜单快捷方式
  CreateDirectory "$SMPROGRAMS\HSLynk"
  CreateShortcut "$SMPROGRAMS\HSLynk\HSLynk.lnk" "$INSTDIR\hslynk.exe"
  CreateShortcut "$DESKTOP\HSLynk.lnk" "$INSTDIR\hslynk.exe"
  
  # 创建卸载程序
  WriteUninstaller "$INSTDIR\uninstall.exe"
  
  # 写入注册表信息
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HSLynk" \
                 "DisplayName" "HSLynk"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HSLynk" \
                 "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HSLynk" \
                 "DisplayIcon" "$INSTDIR\hslynk.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HSLynk" \
                 "Publisher" "Bakacai"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HSLynk" \
                 "DisplayVersion" "1.0.0"
SectionEnd

Section "Uninstall"
  # 删除开始菜单快捷方式
  Delete "$SMPROGRAMS\HSLynk\HSLynk.lnk"
  Delete "$DESKTOP\HSLynk.lnk"
  RMDir "$SMPROGRAMS\HSLynk"
  
  # 删除安装目录
  RMDir /r "$INSTDIR"
  
  # 删除注册表项
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HSLynk"
SectionEnd 