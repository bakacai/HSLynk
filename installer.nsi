!include "MUI2.nsh"

Name "HSLynk"
OutFile "HSLynk-setup.exe"
InstallDir "$PROGRAMFILES64\HSLynk"

!define SOURCE_DIR "build\windows\x64\runner\Release"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "SimpChinese"

Section "HSLynk" SecMain
  SetOutPath "$INSTDIR"

  File /r "${SOURCE_DIR}\*.*"

  CreateDirectory "$SMPROGRAMS\HSLynk"
  CreateShortcut "$SMPROGRAMS\HSLynk\HSLynk.lnk" "$INSTDIR\hslynk.exe"
  CreateShortcut "$DESKTOP\HSLynk.lnk" "$INSTDIR\hslynk.exe"

  WriteUninstaller "$INSTDIR\uninstall.exe"

  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HSLynk" \
                 "DisplayName" "HSLynk"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HSLynk" \
                 "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HSLynk" \
                 "DisplayIcon" "$INSTDIR\hslynk.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HSLynk" \
                 "Publisher" "Bakacai"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HSLynk" \
                 "DisplayVersion" "0.3.0"
SectionEnd

Section "Uninstall"
  # 删除开始菜单快捷方式
  Delete "$SMPROGRAMS\HSLynk\HSLynk.lnk"
  Delete "$DESKTOP\HSLynk.lnk"
  RMDir "$SMPROGRAMS\HSLynk"

  RMDir /r "$INSTDIR"

  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HSLynk"
SectionEnd 