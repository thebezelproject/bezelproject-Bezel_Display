; ============================================================================
;  BEZEL_DISPLAY.AHK  —  MASTER bezel-overlay script (AutoHotkey v2 Native)
; ============================================================================
;
;  What this does:
;     1. Reads WHICH emulator/system "profile" to use from the command line.
;     2. Looks up that profile's settings in profiles.ini (see that file).
;     3. Shows a full-screen black "loading" splash while the emulator boots.
;     4. Finds the matching RetroArch-style bezel PNG for the game/system,
;        or falls back to a default bezel for that system.
;     5. Draws that PNG as a full-screen, click-through, always-on-top,
;        transparent overlay UNDER/around the emulator window, using GDI+.
;     6. Keeps the overlay visible only while the emulator window is active.
;     7. Optionally closes the emulator when you press Escape.
;
;  How it is meant to be called (from a matching master .cmd file):
;     bezel_display.exe "<ProfileName>" "<FullPathToGameFile>"
;
;     Example:
;     bezel_display.exe "bgb_gbc" "D:\Roms\GBC\Pokemon Crystal.gbc"
;
;  Credit: overlay technique adapted from the GDI+ AHK tutorial (tutorial 3)
;  by tic (Tariq Porter) — https://ahkscript.org/boards/viewtopic.php?t=6517
; ============================================================================

; ----------------------------------------------------------------------------
; SECTION 0 — DIRECTIVES  (these all run once, at the very top, before any
;             "real" code executes; they configure how the script behaves)
; ----------------------------------------------------------------------------

#Requires AutoHotkey v2.0
#SingleInstance Force
; If this script (or its compiled .exe) is somehow launched a second time
; while one copy is already running, "Force" tells AHK to kill the old copy
; and let the new one take over, instead of complaining or doing nothing.

; Forces the script to bypass Windows % scaling and use absolute physical pixel layouts
DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr") 

; ----------------------------------------------------------------------------
; SECTION 1 — READ COMMAND-LINE ARGUMENTS
; ----------------------------------------------------------------------------
; A_Args is a built-in AHK array containing every command-line parameter
; the script was launched with, in order: A_Args[1], A_Args[2], etc.
if (A_Args.Length < 2) {
    MsgBox("This script must be launched with two parameters:`n`n"
         . "1) A profile name matching a section in profiles.ini`n"
         . "2) The full path to the game file being launched", 
         "Bezel Display - Missing Parameters", 16)
    ; MsgBox's "16" option means "show the red error/stop icon".
    ; The (\n...\n) continuation section lets a multi-line string span
    ; several lines in the source file for readability.
    ExitApp(1)
}

ProfileName := A_Args[1]   ; e.g. "bgb_gbc"  — which section of profiles.ini to use
GivenPath   := A_Args[2]   ; e.g. "D:\Roms\GBC\Pokemon Crystal.gbc" — the game file

; ----------------------------------------------------------------------------
; SECTION 2 — LOAD THIS PROFILE'S SETTINGS OUT OF profiles.ini
; ----------------------------------------------------------------------------
; IniRead, OutputVar, Filename, Section, Key [, Default]
; This is the classic AHK command for reading a single value out of a
; standard Windows-style .ini file (sections in [brackets], Key=Value lines).
IniFile := A_ScriptDir "\profiles.ini"

if !FileExist(IniFile) {
    MsgBox("Could not find profiles.ini next to this script.`n`nExpected: " IniFile, "Bezel Display - Missing File", 16)
    ExitApp(1)
}

; --- Global / shared setting ---
RAHomeDir := IniRead(IniFile, "Settings", "RAHomeDir", "D:\RetroArch")

; --- Per-profile settings (see the [ProfileName] section in profiles.ini) ---
try {
    ProcessName   := IniRead(IniFile, ProfileName, "ProcessName")
    BezelFolder   := IniRead(IniFile, ProfileName, "BezelFolder")
    DefaultBezel  := IniRead(IniFile, ProfileName, "DefaultBezel")
    PauseTime     := Number(IniRead(IniFile, ProfileName, "PauseTime", "5000"))
    CloseOnEscape := IniRead(IniFile, ProfileName, "CloseOnEscape", "1")
    CloseProcess  := IniRead(IniFile, ProfileName, "CloseProcess", ProcessName)
    IsTRS80       := Number(IniRead(IniFile, ProfileName, "IsTRS80", "0"))
; Notice PauseTime, CloseOnEscape and CloseProcess all supply a 5th
; "Default" parameter — so if a profile's author leaves those out of
; profiles.ini entirely, sensible defaults are used instead of "ERROR".
} catch {
    MsgBox("No [" ProfileName "] section was found in profiles.ini.", "Bezel Display - Unknown Profile", 16)
    ExitApp(1)
}

if (PauseTime == 0) {
    goto section4
}

; ----------------------------------------------------------------------------
; SECTION 3 — SHOW A FULL-SCREEN "LOADING..." SPLASH
; ----------------------------------------------------------------------------
; Most emulators show their own logo / config screens for a second or two
; on startup. This blank black screen hides that so the transition into the
; bezel overlay looks clean. How long it stays up is controlled by the
; PauseTime value we just read from the ini file.
; If your front-end has its own way of handling this, change the PauseTime
; value(s) in profiles.ini to 0

; Create the splash container window and explicitly turn off AHK auto-scaling
GuiBlank := Gui("+AlwaysOnTop +ToolWindow -Caption -Border -DPIScale", "BlankScreen")
; "Gui, Blank: ..." — the "Blank:" is a GUI *name*, letting this script own
; multiple, independently-controlled windows (we'll make a second one,
; named "1", later for the bezel image itself).
;   +AlwaysOnTop  -> stays above other windows
;   +ToolWindow   -> hides it from the Alt+Tab window list / taskbar
;   -Caption      -> no titlebar
;   -Border       -> no window border
GuiBlank.BackColor := "000000" ; Set BackColor to black
GuiBlank.SetFont("s24 cWhite Bold", "Arial")

; Set the text box to take up the EXACT pixel dimension of the display panel.
; Style 0x200 combined with Center forces perfectly aligned Win32 native pixel centering.
GuiBlank.Add("Text", "x0 y0 w" A_ScreenWidth " h" A_ScreenHeight " Center 0x200", "Loading...please wait")
GuiBlank.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)
; A_ScreenWidth / A_ScreenHeight are built-in variables for the primary
; monitor's resolution.

SetTimer(ForceOnTop, 20)
; SetTimer, Label, Period  — repeatedly runs the code under the "ForceOnTop:"
; label every 20 milliseconds, in the background, without blocking the rest
; of the script. See that label near the bottom of this file.

; --- Wait for the game's own startup screens to clear ---
Sleep(PauseTime)
; Sleep pauses the whole script (but timers like ForceOnTop keep firing)
; for the given number of milliseconds — the PauseTime value from the ini.

SetTimer(ForceOnTop, 0)
GuiBlank.Hide()

section4:
; ----------------------------------------------------------------------------
; SECTION 4 — FIGURE OUT WHICH BEZEL IMAGE FILE TO USE
; ----------------------------------------------------------------------------
; RetroArch-style overlay packs store one PNG per game (named after the ROM)
; inside a per-system subfolder, plus one generic "default" PNG per system
; for games that don't have a dedicated bezel yet. We reuse that same
; folder structure here purely as a convenient, already-organized image
; library — no RetroArch process is actually launched.

SplitPath(GivenPath, , , , &FileNameNoExt)
; SplitPath breaks a full path into pieces. The commas with nothing between
; them skip output variables we don't need (FileName, InDir, FileNameExt in
; that order) — we only care about FileNameNoExt here, e.g. "Pokemon Crystal".

RetroarchOverlaysDirectory := RAHomeDir "\overlays\GameBezels\" BezelFolder "\"
if !DirExist(RetroarchOverlaysDirectory) {
    MsgBox(RetroarchOverlaysDirectory " was not found.", "Bezel folder not found", 16)
    ExitApp(1)
}

RetroarchOverlaysDefault := RAHomeDir "\overlays\" DefaultBezel
if !FileExist(RetroarchOverlaysDefault) {
    MsgBox(RetroarchOverlaysDefault " was not found.", "Default bezel not found", 16)
    ExitApp(1)
}

; Check if the profile being used is the one defined as trs80gp
; trs80gp assumes use of TOSEC formatted files/paths, including programs, texts, etc.
; trs80gp bezels look for the directory name instead of the file name like other bezels
if (IsTRS80 == 0) {
    RetroarchOverlaysBezel := RetroarchOverlaysDirectory FileNameNoExt ".png"
} else {
    SplitPath(GivenPath, , &outDir)
    SplitPath(outDir, &outFileName)
    RetroarchOverlaysBezel := RetroarchOverlaysDirectory outFileName ".png"
}

fName := !FileExist(RetroarchOverlaysBezel) ? RetroarchOverlaysDefault : RetroarchOverlaysBezel
; RetroarchOverlaysDefault    ; no game-specific bezel -> use the system default
; RetroarchOverlaysBezel      ; found a bezel matching this exact game

; ----------------------------------------------------------------------------
; SECTION 5 — DRAW THE BEZEL IMAGE AS A LAYERED OVERLAY VIA NATIVE GDI+
; ----------------------------------------------------------------------------

; Startup Native GDI+ Context
gdiplusToken := 0
si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
NumPut("UInt", 1, si, 0) ; GdiplusVersion = 1
if DllCall("gdiplus\GdiplusStartup", "Ptr*", &gdiplusToken, "Ptr", si, "Ptr", 0) {
    MsgBox("Gdiplus failed to start.", "gdiplus error!", 48)
    ExitApp(1)
}

; Setup Automatic Clean Exit Routing Routine
OnExit(CleanExit)
; Tells AHK: no matter HOW this script ends (normal exit, user closes it,
; Windows shuts down, etc.), run the code under the "CleanExit:" label first so
; we can clean up GDI+ properly. See that label near the bottom.

Gui1 := Gui("-Caption +E0x80000 +LastFound +AlwaysOnTop +ToolWindow +OwnDialogs")
Gui1.Show("NA")
Gui1.Hide()
; This little show/hide dance forces Windows to actually create window "1"
; (with the styles we requested) before we grab its handle below — a window
; that's never been shown doesn't reliably have a usable HWND yet.
;   +E0x80000   -> WS_EX_LAYERED extended style: required for a translucent /
;                  per-pixel-alpha window (what makes the bezel's transparent
;                  areas actually show the emulator through them).
;   +LastFound  -> makes this the implicit target of the WinExist() call below.
;   +OwnDialogs -> any MsgBox etc. popped up by this script attaches to it.
hwnd1 := Gui1.Hwnd
; Grabs the window handle (a unique numeric ID Windows uses internally) of
; the "last found" window, i.e. the Gui 1 window we just created.

; Load the Target PNG Graphic Natively
pBitmap := 0
if DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", fName, "Ptr*", &pBitmap) != 0 || !pBitmap {
    MsgBox("Could not load file: '" fName "'", "File loading error!", 48)
    ExitApp(1)
}

; Resolve Matrix Metrics Data
imgWidth := 0, imgHeight := 0
DllCall("gdiplus\GdipGetImageWidth", "Ptr", pBitmap, "UInt*", &imgWidth)
DllCall("gdiplus\GdipGetImageHeight", "Ptr", pBitmap, "UInt*", &imgHeight)

; Setup Device Buffers and Layer Elements
hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
hdc       := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")

; Create an optimization system via Device Independent Bitmap structures
bi := Buffer(40, 0)
NumPut("UInt", 40,              bi, 0)  ; biSize (Type first!)
NumPut("Int",  A_ScreenWidth,   bi, 4)  ; biWidth
NumPut("Int",  -A_ScreenHeight, bi, 8)  ; biHeight (Negative value = top-down DIB)
NumPut("UShort", 1,             bi, 12) ; biPlanes
NumPut("UShort", 32,            bi, 14) ; biBitCount (32-bit for alpha transparency handling)
NumPut("UInt", 0,               bi, 16) ; biCompression = BI_RGB

hbm := DllCall("CreateDIBSection", "Ptr", hdc, "Ptr", bi, "UInt", 0, "Ptr*", 0, "Ptr", 0, "UInt", 0, "Ptr")
obm := DllCall("SelectObject", "Ptr", hdc, "Ptr", hbm, "Ptr")

; Bind Graphics and Apply Scaling Quality Optimization Engine
pGraphics := 0
DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pBitmap, "Ptr*", &pGraphics) ; Fallback initializer
DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics) ; flush temporary state
DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdc, "Ptr*", &pGraphics)
DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", pGraphics, "Int", 7) ; 7 = HighQualityBicubic Engine

; Draw Target Frame Matrix Stretched onto the Buffer
DllCall("gdiplus\GdipDrawImageRectRect", "Ptr", pGraphics, "Ptr", pBitmap
    , "Float", 0, "Float", 0, "Float", A_ScreenWidth, "Float", A_ScreenHeight ; Target
    , "Float", 0, "Float", 0, "Float", imgWidth, "Float", imgHeight           ; Source
    , "Int", 2, "Ptr", 0, "Ptr", 0, "Ptr", 0)

; Perform Hardware Update to Layer Window Element Pipeline
; FIXED: Building a formal POINT structure specifying explicit X=0, Y=0 positioning
ptZero := Buffer(8, 0) 
NumPut("Int", 0, ptZero, 0) ; Target Screen Coordinate X = 0
NumPut("Int", 0, ptZero, 4) ; Target Screen Coordinate Y = 0

sizeWH := Buffer(8, 0)
NumPut("Int", A_ScreenWidth,  sizeWH, 0)
NumPut("Int", A_ScreenHeight, sizeWH, 4)

blend := Buffer(4, 0)
NumPut("UChar", 0,   blend, 0) ; AC_SRC_OVER
NumPut("UChar", 0,   blend, 1) ; AC_SRC_ALPHA
NumPut("UChar", 255, blend, 2) ; SourceConstantAlpha (Full Opacity)
NumPut("UChar", 1,   blend, 3) ; AC_SRC_ALPHA flag layout

; FIXED: Passing the ptZero buffer pointer variable directly as the 3rd parameter instead of raw 0
DllCall("UpdateLayeredWindow", "Ptr", hwnd1, "Ptr", hdcScreen, "Ptr", ptZero, "Ptr", sizeWH
    , "Ptr", hdc, "Ptr", ptZero, "UInt", 0, "Ptr", blend, "UInt", 2) ; 2 = ULW_ALPHA

; Cleanup Local GDI Handlers instantly
DllCall("SelectObject", "Ptr", hdc, "Ptr", obm, "Ptr")
DllCall("DeleteObject", "Ptr", hbm)
DllCall("DeleteDC", "Ptr", hdc)
DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)

; ----------------------------------------------------------------------------
; SECTION 6 — OPTIONAL ESCAPE HOTKEY ORCHESTRATION
; ----------------------------------------------------------------------------
if (CloseOnEscape == "1") {
    Hotkey("~Escape", EscapeHandler)
    ; Hotkey, KeyName, Label  — dynamically creates a hotkey that jumps to
    ; the given label when pressed. The "~" prefix (kept from the key name
    ; itself, same meaning as in a normal ::hotkey definition) means "let
    ; the Escape keystroke still pass through to whatever app is focused,
    ; don't swallow it" — so the emulator also sees the Escape key.
}

SetTimer(Tick, 200)
; Starts the recurring "tick" subroutine (Section 7 below) that shows/hides
; the bezel depending on whether the emulator window is currently active.
; This must be started here, in the auto-execute section, BEFORE the
; Return below — labels/subroutines lower in the file only ever run when
; something (this timer, a hotkey, OnExit) triggers them.
return
; This bare "Return" marks the end of the script's automatically-executed
; top section. Everything below is either a hotkey handler, a timer
; sub-routine, or a named label — none of it runs until something (a timer
; tick, a hotkey press, OnExit, etc.) triggers it.

; ----------------------------------------------------------------------------
; SECTION 7 — SUBROUTINES / EVENTS
; ----------------------------------------------------------------------------

EscapeHandler(HotkeyName) {
    ; Runs only if CloseOnEscape=1 for this profile (see Section 6 above).
    if ProcessExist(CloseProcess)
        ProcessClose(CloseProcess)
}

Tick() {
    ; Fired every 200ms by the SetTimer call below. Keeps the bezel window
    ; shown only while the actual emulator window is the active/focused one
    ; — so if you Alt+Tab away, the bezel politely hides instead of
    ; floating over your desktop.
    global Gui1 ; REQUIRED: Allows the function to access the global Gui1 object
    if WinActive("ahk_exe " ProcessName) {
        ; Enforce Window properties dynamically while Active
        Gui1.Opt("+AlwaysOnTop +ToolWindow -Caption")
        Gui1.Show("NA")
    } else {
        Gui1.Hide()
    }
}

ForceOnTop() {
    ; Fired every 20ms ONLY during the initial loading splash (Section 3),
    ; repeatedly re-asserting "always on top" so nothing the emulator does
    ; during its own startup can steal focus/topmost status away from our
    ; black loading screen.
    global GuiBlank ; REQUIRED: Allows the function to access the global GuiBlank object
    GuiBlank.Opt("+AlwaysOnTop")
    WinSetAlwaysOnTop(True, "BlankScreen")
    WinMoveTop("BlankScreen") ; FIXED: Replaces the invalid WinSetTop function
}

CleanExit(ExitReason, ExitCode) {
    ; Runs automatically on ANY exit path, because of "OnExit, Exit" above.
    global gdiplusToken ; REQUIRED: Allows the function to modify the global token variable
    SetTimer(Tick, 0)
    if (gdiplusToken) {
        DllCall("gdiplus\GdiplusShutdown", "Ptr", gdiplusToken)
        gdiplusToken := 0
    }
}
