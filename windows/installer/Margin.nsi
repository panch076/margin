; Margin for Windows - installer script (NSIS 3).
;
; Build the app first (see README), then:
;   makensis -DVERSION=1.0.0 -DEXE=..\out\Margin.exe Margin.nsi
;
; Installs for the current user only, so it never asks for administrator rights.
; Run with /S for a silent install: the app's updater does this, and the new version opens afterwards.

Unicode true
ManifestDPIAware true
!include "MUI2.nsh"

!define APPNAME "Margin"
!ifndef VERSION
  !define VERSION "1.0.0"
!endif
!ifndef EXE
  !define EXE "..\out\Margin.exe"
!endif
!ifndef OUTFILE
  !define OUTFILE "Margin-Setup-${VERSION}.exe"
!endif
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"

Name "${APPNAME}"
OutFile "${OUTFILE}"
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\Programs\${APPNAME}"
InstallDirRegKey HKCU "Software\${APPNAME}" "InstallDir"
SetCompress off            ; Margin.exe is already compressed internally
BrandingText "${APPNAME} ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APPNAME}"
VIAddVersionKey "FileDescription" "${APPNAME} Setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" ""

!define MUI_ICON "..\Margin.App\Assets\Margin.ico"
!define MUI_UNICON "..\Margin.App\Assets\Margin.ico"
!define MUI_ABORTWARNING
!define MUI_COMPONENTSPAGE_NODESC
!define MUI_FINISHPAGE_RUN "$INSTDIR\Margin.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Open Margin"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Margin" SecApp
  SectionIn RO

  ; When the app updates itself it starts this installer and then exits.
  ; Wait (up to about 15 seconds) until the old Margin.exe is no longer in use.
  StrCpy $0 0
  wait_for_exit:
    IfFileExists "$INSTDIR\Margin.exe" 0 ready
    ClearErrors
    FileOpen $1 "$INSTDIR\Margin.exe" a
    IfErrors 0 unlocked
    IntOp $0 $0 + 1
    IntCmp $0 60 ready
    Sleep 250
    Goto wait_for_exit
  unlocked:
    FileClose $1
  ready:

  SetOutPath "$INSTDIR"
  File "/oname=Margin.exe" "${EXE}"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateShortcut "$SMPROGRAMS\${APPNAME}.lnk" "$INSTDIR\Margin.exe"

  WriteRegStr HKCU "Software\${APPNAME}" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayIcon" "$INSTDIR\Margin.exe"
  WriteRegStr HKCU "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTKEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${UNINSTKEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoRepair" 1
  WriteRegDWORD HKCU "${UNINSTKEY}" "EstimatedSize" 61000
SectionEnd

Section "Desktop shortcut" SecDesktop
  ; A silent run is an update: leave the desktop the way the user has it.
  IfSilent +2
  CreateShortcut "$DESKTOP\${APPNAME}.lnk" "$INSTDIR\Margin.exe"
SectionEnd

; After a silent install (an in-app update), open the new version.
Function .onInstSuccess
  IfSilent 0 +2
  Exec '"$INSTDIR\Margin.exe"'
FunctionEnd

Section "Uninstall"
  Delete "$INSTDIR\Margin.exe"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\${APPNAME}.lnk"
  Delete "$DESKTOP\${APPNAME}.lnk"
  DeleteRegKey HKCU "${UNINSTKEY}"
  DeleteRegKey HKCU "Software\${APPNAME}"

  ; The downloaded question bank and your results live in a separate folder. Keep them unless asked.
  IfFileExists "$LOCALAPPDATA\${APPNAME}\*.*" 0 done
    MessageBox MB_YESNO|MB_ICONQUESTION "Also delete the downloaded question bank and your saved results?" /SD IDNO IDNO done
    RMDir /r "$LOCALAPPDATA\${APPNAME}"
  done:
SectionEnd
