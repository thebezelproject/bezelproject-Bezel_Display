; ============================================================================
;  PROFILE_EDITOR.AHK  —  GUI editor for profiles.ini  (AutoHotkey v2)
; ============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
ListLines False
KeyHistory 0
SendMode "Input"
SetWorkingDir A_ScriptDir

; ----------------------------------------------------------------------------
; SECTION 1 — GLOBAL STATE
; ----------------------------------------------------------------------------
global IniFile := A_ScriptDir . "\profiles.ini"
global MaxFields := 12

global StandardKeys := ["BezelFolder", "CloseOnEscape", "CloseProcess", "DefaultBezel", "EmulatorArgs", "EmulatorExe",
    "EmulatorPathVar", "IsTRS80", "PauseTime", "ProcessName"]

global KeyDescriptions := Map(
    "BezelFolder", "Path to the directory containing bezel images and config files for this system.",
    "CloseOnEscape",
    "Set to true=1 if pressing the Escape key should immediately close this emulator environment. False=0, if not.",
    "CloseProcess", "Force-kills this specific backend task name upon exiting the frontend launcher.",
    "DefaultBezel", "The fallback image filename used if no game-specific bezel artwork matches.",
    "EmulatorArgs", "Command-line parameters and arguments passed directly to the emulator executable.",
    "EmulatorExe", "The exact filename of the emulator binary executable (e.g., nestopia.exe).",
    "EmulatorPathVar", "System environment variable string mapping to the main emulator installation directory.",
    "IsTRS80", "Flipped flag (true=1/false=0) to handle unusual core aspect ratios specific to TRS-80 systems.",
    "PauseTime", "Delay duration in milliseconds to wait for the window to focus before loading artwork.",
    "ProcessName", "The target process loop string monitored to track whether the game is currently running."
)

global CurrentSection := ""
global IsNewSection := false
global Dirty := false
global NumFieldsLoaded := 0

global LabelMap := Map()
global EditMap := Map()

; ----------------------------------------------------------------------------
; SECTION 2 — STARTUP CHECK
; ----------------------------------------------------------------------------
if !FileExist(IniFile) {
    ; Added 262144 to the options parameter (16 + 262144 = 262160)
    MsgBox("Could not find profiles.ini next to this script.`n`nExpected: " . IniFile, "profiles.ini not found", 262160
    )
    ExitApp()
}

; ----------------------------------------------------------------------------
; SECTION 3 — BUILD THE GUI
; ----------------------------------------------------------------------------
MyGui := Gui("+AlwaysOnTop", "Bezel Profile Editor")

; Set font size early to handle 150% DPI scaling layout coordinates dynamically
MyGui.SetFont("s10", "Segoe UI")

; --- Left side: the scrollable profile list ---
LV1 := MyGui.Add("ListView", "x10 y10 w230 h430 cWhite BackgroundBlue Grid -Multi Sort", ["Profile"])

; --- Right side: Section Name field (always visible) ---
MyGui.Add("Text", "x260 y10 w130", "Section Name:")
MyGui.SetFont("s7")
MyGui.Add("Text", "x260 y30 w130", "(emulatorName_systemName)")
MyGui.SetFont("s10")
SectionNameEdit := MyGui.Add("Edit", "x400 y10 w330")

; --- Right side: Dynamic generated (Label, Edit) pairs ---
loop MaxFields {
    y := 46 + ((A_Index - 1) * 32)

    lblCtrl := MyGui.Add("Text", "x260 y" . y . " w130 Hidden", "")
    editCtrl := MyGui.Add("Edit", "x400 y" . y . " w330 Hidden", "")

    LabelMap[A_Index] := lblCtrl
    EditMap[A_Index] := editCtrl
}

; --- Bottom: action buttons ---
BtnNewCtrl := MyGui.Add("Button", "x400 y460 w80", "New")
BtnSaveCtrl := MyGui.Add("Button", "x490 y460 w80", "Save")
BtnCancelCtrl := MyGui.Add("Button", "x580 y460 w80", "Cancel")
BtnExitCtrl := MyGui.Add("Button", "x670 y460 w80", "Exit")

; --- Status bar ---
SB := MyGui.Add("StatusBar", , "Ready.")

; Custom draw hook configurations
HHDR := DllCall("SendMessage", "Ptr", LV1.Hwnd, "UInt", 0x101F, "Ptr", 0, "Ptr", 0, "UPtr") ; LVM_GETHEADER
global HeaderColors := Map()
HeaderColors[HHDR] := { Txt: 0xFFFFFF, Bkg: 0x660000 }

; ----------------------------------------------------------------------------
; SECTION 4 — EVENT MAPPING AND INITIAL SHOW
; ----------------------------------------------------------------------------
; In AHK v2, all events must be mapped explicitly before functions are defined
MyGui.OnEvent("Close", GuiClose)
MyGui.OnEvent("Escape", GuiEscape)
LV1.OnEvent("Click", LV1Event)       ; Triggers on a single click
LV1.OnEvent("DoubleClick", LV1Event) ; Triggers on a double-click
LV1.OnEvent("ItemSelect", LV1Event)  ; Triggers when changing rows via arrow keys or mouse [1]
SectionNameEdit.OnEvent("Change", FieldChanged)

loop MaxFields {
    EditMap[A_Index].OnEvent("Change", FieldChanged)
}

BtnNewCtrl.OnEvent("Click", BtnNew)
BtnSaveCtrl.OnEvent("Click", BtnSave)
BtnCancelCtrl.OnEvent("Click", BtnCancel)
BtnExitCtrl.OnEvent("Click", BtnExit)

SubclassControl(LV1.Hwnd, "HeaderCustomDraw")
OnMessage(0x0200, WM_MOUSEMOVE)

; Final Presentation initialization
MyGui.Show("w770 h525")
RefreshListView()
return  ; Formally ends the script's Auto-Execute environment. Functions sit safely below.

; ----------------------------------------------------------------------------
; SECTION 5 — GUI EVENT FUNCTIONS
; ----------------------------------------------------------------------------

FieldChanged(GuiCtrlObj, Info) {
    global Dirty := true
}

LV1Event(GuiCtrlObj, Item, *) {
    global CurrentSection, IsNewSection, Dirty

    RowNum := LV1.GetNext(0, "Focused")
    if (!RowNum)
        return

    SelSection := LV1.GetText(RowNum, 1)

    if (SelSection = CurrentSection and !IsNewSection)
        return

    if (Dirty) {
        ; Added 262144 to the options parameter (4 + 262144 = 262148)
        Answer := MsgBox("You have unsaved changes to `" " . CurrentSection .
            "`".`n`nDiscard them and switch profiles?", "Unsaved changes", 262148)
        if (Answer = "No") {
            ReselectCurrentRow()
            return
        }
    }

    SelectSection(SelSection)
}

BtnNew(GuiCtrlObj, Info) {
    global IsNewSection, CurrentSection, NumFieldsLoaded, Dirty
    if (Dirty) {
        ; Added 262144 to the options parameter (4 + 262144 = 262148)
        Answer := MsgBox("You have unsaved changes to `" " . CurrentSection .
            "`".`n`nDiscard them and start a new profile?", "Unsaved changes", 262148)
        if (Answer = "No")
            return
    }

    IsNewSection := true
    CurrentSection := ""

    LV1.Modify(0, "-Select")
    SectionNameEdit.Value := ""

    loop StandardKeys.Length {
        LabelMap[A_Index].Value := StandardKeys[A_Index]
        EditMap[A_Index].Value := ""
        LabelMap[A_Index].Visible := true
        EditMap[A_Index].Visible := true
    }
    NumFieldsLoaded := StandardKeys.Length

    loop MaxFields {
        if (A_Index > NumFieldsLoaded) {
            LabelMap[A_Index].Visible := false
            EditMap[A_Index].Visible := false
        }
    }

    Dirty := false
    SectionNameEdit.Focus()
    SB.SetText("Enter a new profile name and values, then click Save.")
}

BtnSave(GuiCtrlObj, Info) {
    global IsNewSection, CurrentSection, Dirty, NumFieldsLoaded

    NewName := Trim(SectionNameEdit.Value)

    if (NewName == "") {
        MsgBox("Please enter a profile (section) name before saving.", "Missing profile name", 48)
        return
    }

    if (SectionExists(NewName) and NewName != CurrentSection) {
        MsgBox("A profile named `" " . NewName . "`" already exists.`n`nChoose a different name.", "Duplicate profile",
            48)
        return
    }

    if (!IsNewSection and CurrentSection != "" and NewName != CurrentSection)
        IniDelete(IniFile, CurrentSection)

    loop NumFieldsLoaded {
        kName := LabelMap[A_Index].Value
        kVal := EditMap[A_Index].Value
        if (kName == "")
            continue
        IniWrite(kVal, IniFile, NewName, kName)
    }

    IsNewSection := false
    CurrentSection := NewName
    Dirty := false

    RefreshListView()
    SB.SetText("Saved profile: " . NewName)
}

BtnCancel(GuiCtrlObj, Info) {
    global IsNewSection, CurrentSection, Dirty
    if (IsNewSection) {
        IsNewSection := false
        LV1.Modify(0, "-Select")
        ClearRightPanel()
        SB.SetText("New profile discarded.")
    }
    else if (CurrentSection != "") {
        SelectSection(CurrentSection)
        SB.SetText("Changes discarded.")
    }
    Dirty := false
}

BtnExit(GuiCtrlObj, Info) {
    GuiClose(MyGui)
}

GuiClose(GuiObj) {
    global Dirty
    if (Dirty) {
        ; Added 262144 to the options parameter (4 + 262144 = 262148)
        Answer := MsgBox("You have unsaved changes.`n`nExit anyway and discard them?", "Unsaved changes", 262148)
        if (Answer = "No")
            return true
    }
    ExitApp()
}

GuiEscape(GuiObj) {
    return GuiClose(GuiObj)
}

; ----------------------------------------------------------------------------
; SECTION 6 — TOOLTIP HANDLER
; ----------------------------------------------------------------------------
WM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
    static LastHwnd := 0
    if (hwnd != LastHwnd) {
        LastHwnd := hwnd
        ToolTip()

        for index, editCtrl in EditMap {
            if (editCtrl.Hwnd == hwnd && editCtrl.Visible) {
                associatedKey := LabelMap[index].Value
                if (associatedKey != "") {
                    descText := KeyDescriptions.Has(associatedKey) ? KeyDescriptions[associatedKey] :
                        "Custom profile field parameter."
                    ToolTip("Key: " . associatedKey . "`n`n" . descText)
                    SetTimer () => ToolTip(), -4000
                }
                break
            }
        }
    }
}

; ----------------------------------------------------------------------------
; SECTION 7 — UTILITY FUNCTIONS
; ----------------------------------------------------------------------------

SelectSection(SectionName) {
    global CurrentSection, IsNewSection, Dirty, NumFieldsLoaded

    ; 1. Clear everything FIRST to reset the panel cleanly
    ClearRightPanel()

    ; 2. NOW assign the new values safely
    IsNewSection := false
    CurrentSection := SectionName
    SectionNameEdit.Value := SectionName

    ; Always loop through the full schema defined in StandardKeys (all 10 fields)
    loop StandardKeys.Length {
        kName := StandardKeys[A_Index]

        ; Try to read the value from the ini file. If it doesn't exist, default to blank ("")
        try {
            kVal := IniRead(IniFile, SectionName, kName)
        } catch {
            kVal := ""
        }

        ; Assign name and value to the GUI elements
        LabelMap[A_Index].Value := kName
        EditMap[A_Index].Value := kVal

        ; Make them visible on the right panel
        LabelMap[A_Index].Visible := true
        EditMap[A_Index].Visible := true
    }

    ; Track that all template fields are active for saving
    NumFieldsLoaded := StandardKeys.Length
    Dirty := false
    SB.SetText("Editing profile: " . SectionName)
}

ClearRightPanel() {
    SectionNameEdit.Value := ""
    loop MaxFields {
        LabelMap[A_Index].Value := ""
        EditMap[A_Index].Value := ""
        LabelMap[A_Index].Visible := false
        EditMap[A_Index].Visible := false
    }
}

RefreshListView() {
    LV1.Delete()

    ; Fix: Read the entire file as a direct string to avoid the broken Windows ANSI API
    try {
        fileContent := FileRead(IniFile, "UTF-8") ; Explicitly reads as UTF-8 safely
    } catch {
        fileContent := ""
    }

    ; Parse line-by-line looking for standard ini structural [SectionName] brackets
    loop parse, fileContent, "`n", "`r" {
        trimmedLine := Trim(A_LoopField)

        ; Match strings that start with '[' and end with ']'
        if (SubStr(trimmedLine, 1, 1) = "[" and SubStr(trimmedLine, -1) = "]") {
            ; Strip the outer [ and ] brackets out to grab the clean section text name
            secName := SubStr(trimmedLine, 2, StrLen(trimmedLine) - 2)
            secName := Trim(secName)

            if (secName != "" and secName != "Settings")
                LV1.Add("", secName)
        }
    }

    LV1.ModifyCol(1, "AutoHdr")
    ReselectCurrentRow()
}

ReselectCurrentRow() {
    loop LV1.GetCount() {
        t := LV1.GetText(A_Index, 1)
        if (t = CurrentSection) {
            LV1.Modify(A_Index, "Select Focus")
            break
        }
    }
}

SectionExists(name) {
    try {
        list := IniRead(IniFile)
    } catch {
        list := ""
    }
    Sections := StrSplit(list, "n", "r")
    for idx, sec in Sections
        if (sec = name)
            return true
    return false
}

HeaderCustomDraw(H, M, W, L, IdSubclass, RefData) {
    static NM_CUSTOMDRAW := -12
    static CDRF_DODEFAULT := 0x00000000
    static CDRF_SKIPDEFAULT := 0x00000004
    static CDRF_NOTIFYITEMDRAW := 0x00000020
    static CDDS_PREPAINT := 0x00000001
    static CDDS_ITEMPREPAINT := 0x00010001
    static DC_Brush := DllCall("GetStockObject", "UInt", 18, "UPtr")
    static OHWND := 0
    static OMsg := (2 * A_PtrSize)
    static ODrawStage := OMsg + A_PtrSize
    static OHDC := ODrawStage + A_PtrSize
    static ORect := OHDC + A_PtrSize
    static OItemSpec := OHDC + 16 + A_PtrSize
    static LM := 4
    static TM := 6
    global HeaderColors
    if (M = 0x4E) {
        HWND := NumGet(L + OHWND, "UPtr")
        if HeaderColors.Has(HWND) {
            HC := HeaderColors[HWND]
            Code := NumGet(L + OMsg, "Int")
            if (Code = NM_CUSTOMDRAW) {
                DrawStage := NumGet(L + ODrawStage, "UInt")
                if (DrawStage = CDDS_ITEMPREPAINT) {
                    Item := NumGet(L + OItemSpec, "Ptr")
                    HDITEM := Buffer(24 + (6 * A_PtrSize), 0)
                    ItemTxt := Buffer(520, 0)
                    NumPut("UInt", 0x86, HDITEM, 0)
                    NumPut("Ptr", ItemTxt.Ptr, HDITEM, 8)
                    NumPut("Int", 260, HDITEM, 8 + (2 * A_PtrSize))
                    DllCall("SendMessage", "Ptr", HWND, "UInt", 0x120B, "Ptr", Item, "Ptr", HDITEM.Ptr)
                    Fmt := NumGet(HDITEM, 12 + (2 * A_PtrSize), "UInt") & 3
                    Order := NumGet(HDITEM, 20 + (3 * A_PtrSize), "Int")
                    HDC := NumGet(L + OHDC, "Ptr")
                    if (Item = 0 && Order = 0)
                        NumPut("Int", NumGet(L + ORect, "Int") + LM, L + ORect, "Int")
                    DllCall("SetDCBrushColor", "Ptr", HDC, "UInt", HC.Bkg)
                    DllCall("FillRect", "Ptr", HDC, "Ptr", L + ORect, "Ptr", DC_Brush)
                    if (Item = 0 && Order = 0)
                        NumPut("Int", NumGet(L + ORect, "Int") - LM, L + ORect, "Int")
                    DllCall("SetBkMode", "Ptr", HDC, "UInt", 0)
                    DllCall("SetTextColor", "Ptr", HDC, "UInt", HC.Txt)
                    DllCall("InflateRect", "Ptr", L + ORect, "Int", -TM, "Int", 0)
                    DT_ALIGN := 0x0224 + ((Fmt & 1) ? 2 : (Fmt & 2) ? 1 : 0)
                    DllCall("DrawText", "Ptr", HDC, "Ptr", ItemTxt.Ptr, "Int", -1, "Ptr", L + ORect, "UInt", DT_ALIGN)
                    return CDRF_SKIPDEFAULT
                }
                return (DrawStage = CDDS_PREPAINT) ? CDRF_NOTIFYITEMDRAW : CDRF_DODEFAULT
            }
        }
    } else if (M = 0x02) {
        SubclassControl(H, "")
    }
    return DllCall("DefSubclassProc", "Ptr", H, "UInt", M, "Ptr", W, "Ptr", L, "Ptr")
}

SubclassControl(HCTL, FuncName, Data := 0) {
    static ControlCB := Map()
    if ControlCB.Has(HCTL) {
        DllCall("RemoveWindowSubclass", "Ptr", HCTL, "Ptr", ControlCB[HCTL], "Ptr", HCTL)
        ControlCB.Delete(HCTL)
        if (FuncName = "")
            return true
    }
    if !DllCall("IsWindow", "Ptr", HCTL, "UInt") || (FuncName = "")
        return false
    try {
        funcObj := %FuncName%
    } catch {
        return false
    }
    if !(CB := CallbackCreate(funcObj, , 6))
        return false
    if !DllCall("SetWindowSubclass", "Ptr", HCTL, "Ptr", CB, "Ptr", HCTL, "Ptr", Data) {
        CallbackFree(CB)
        return false
    }
    ControlCB[HCTL] := CB
    return true
}
