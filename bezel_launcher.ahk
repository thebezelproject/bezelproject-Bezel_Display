#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon

; =============================================================================
;  BEZEL_LAUNCHER.AHK  —  MASTER launcher (Replaces bezel_launcher.cmd)
; =============================================================================
;  Usage:
;      bezel_launcher.exe "<ProfileName>" "<FullPathToGameFile>"
;
;  Example:
;      bezel_launcher.exe "bgb_gbc" "D:\Roms\GBC\Pokemon Crystal.gbc"
;
;  What it does:
;      1. Looks up shared path variables from _paths.ini (emulator
;         install folders, etc. — one place to update if you move something).
;      2. Looks up this profile's emulator settings in profiles.ini.
;      3. Launches bezel_display.exe (the AHK master script) in the
;         background, telling it which profile + game to show a bezel for.
;      4. Launches the real emulator and waits for it to close.
;      5. Kills the bezel overlay once the emulator exits.
; =============================================================================

if (A_Args.Length < 2) {
    MsgBox("Usage: bezel_launcher.exe `"ProfileName`" `"FullPathToGameFile`"`n`n"
         . "ProfileName: Must match a [SectionName] in profiles.ini`n"
         . "FullPathToGameFile: The ROM/disc image being launched", 
         "Bezel Launcher - Missing Parameters", 16)
    ExitApp(1)
}

ProfileName := A_Args[1]
GamePath    := A_Args[2]

; --- 1. Load shared path variables from _paths.ini ---
PathsFile := A_ScriptDir "\_paths.ini"
IniFile   := A_ScriptDir "\profiles.ini"

if !FileExist(IniFile) {
    MsgBox("Could not find profiles.ini next to this script.`n`nExpected: " IniFile, "Error", 16)
    ExitApp(1)
}

; --- 2. Look up this profile's settings in profiles.ini ---
try {
    EmuPathVar   := IniRead(IniFile, ProfileName, "EmulatorPathVar")
    EmuExe       := IniRead(IniFile, ProfileName, "EmulatorExe")
    EmuArgs      := IniRead(IniFile, ProfileName, "EmulatorArgs", "")
    PauseTime    := IniRead(IniFile, ProfileName, "PauseTime", "5000")
} catch {
    MsgBox("No [" ProfileName "] section with valid entries was found in profiles.ini.", "Profile Error", 16)
    ExitApp(1)
}

; --- 3. Resolve the emulator's install folder ---
try {
    CleanPath := IniRead(PathsFile, "Paths", EmuPathVar)
} catch {
    MsgBox("Could not resolve path variable: " EmuPathVar "`nEnsure it is defined in _paths.ini", "Path Error", 16)
    ExitApp(1)
}

; Clean trailing backslashes and quotes dynamically
CleanPath := RTrim(StrReplace(CleanPath, '"'), "\")
GamePath  := RTrim(StrReplace(GamePath, '"'), "\")

; --- 4. Start the bezel overlay script ---
; Spawns bezel_display in the background. It passes the profile and clean game path down.
BezelPID := 0
try {
    ; Runs either the compiled executable or passes it directly to the AHK interpreter
    if FileExist(A_ScriptDir "\bezel_display.exe")
        Run('"' A_ScriptDir '\bezel_display.exe" "' ProfileName '" "' GamePath '"',,, &BezelPID)
    else
        Run('"' A_AhkPath '" "' A_ScriptDir '\bezel_display.ahk" "' ProfileName '" "' GamePath '"',,, &BezelPID)
} catch {
    MsgBox("Failed to launch bezel_display script.", "Error", 16)
}

; --- 5. Run the emulator and wait for it to close ---
EmuCommand := '"' CleanPath '\' EmuExe '" ' EmuArgs ' "' GamePath '"'
try {
    RunWait(EmuCommand, CleanPath)
} catch {
    MsgBox("Failed to execute emulator command:`n" EmuCommand, "Execution Error", 16)
}

; --- 6. Clean up the bezel overlay ---
if (BezelPID) {
    ProcessClose(BezelPID)
} else {
    ; Fallback safety kill matching the original cmd script
    if ProcessExist("bezel_display.exe")
        ProcessClose("bezel_display.exe")
}

ExitApp(0)
