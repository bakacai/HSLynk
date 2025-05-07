!include "MUI2.nsh"

Name "HSLynk"
OutFile "HSLynk-setup.exe"
InstallDir "$PROGRAMFILES64\HSLynk"

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "SimpChinese"

Section "HSLynk" SecMain
  SetOutPath "$INSTDIR"
  File /r "..\build\windows\x64\runner\Release\*.*"
  
  CreateDirectory "$SMPROGRAMS\HSLynk"
  CreateShortcut "$SMPROGRAMS\HSLynk\HSLynk.lnk" "$INSTDIR\hslynk.exe"
  CreateShortcut "$DESKTOP\HSLynk.lnk" "$INSTDIR\hslynk.exe"
  
  WriteUninstaller "$INSTDIR\uninstall.exe"
  
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HSLynk" \
                 "DisplayName" "HSLynk"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HSLynk" \
                 "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\HSLynk\HSLynk.lnk"
  Delete "$DESKTOP\HSLynk.lnk"
  RMDir "$SMPROGRAMS\HSLynk"
  
  RMDir /r "$INSTDIR"
  
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HSLynk"
SectionEnd 