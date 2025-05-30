#Requires AutoHotkey v2.0
#SingleInstance Force

; Do a playback from this file to generate a demo
demoFilePath := A_ScriptDir "\demo-script.md"
; Key sequence is enclosed by "`" - all other text is typed
; normally. A key sequence may start with "#", then it is just
; sent, else it is typed and saved for playback by the sequence
; "#". The key syntax is slightly more readable than AHKs and
; "´" is quote (not "`") and there are special sequences:
; - cls: clear screen
; - exit: exit app
; - dT[,K]: delay typing by T ms and key sequences by K ms
; - dT=[,K]: set default delays - the command above will reset them at start of a sequence
; - wD: wait D*100 ms
; - loop,C,K: COUNT times sends seq

; Must be higher than the InputLevel of the receiving script, i.e. Emoji Keyboard
SendLevel(10)
; Must be true to find hidden script windows
DetectHiddenWindows(true)
; Match part of the title
SetTitleMatchMode(2)

; I tried it with Notepad, but used VS Code buffer "demo.md" then.
; Check if a Notepad window already exists
; notepadTitle := "ahk_class Notepad"
; if WinExist(notepadTitle) {
;     WinActivate(notepadTitle)
; }
; else { ; if Notepad is not found, launch it
;     Run("notepad.exe")
; }
; WinWait(notepadTitle)

F12:: ExitApp()

MsgBox("Set focus to the editor window/buffer to insert to.`n" .
       "Start screen recording and do not change focus!`n" .
       "Make sure the mouse does not go in the way!`n" .
       "Press F12 to abort execution of this script!`n" .
       "If you are ready press OK to start playback.", , 0x1000)

if (A_Args.Length < 1) {
    content := StrReplace(FileRead(DemoFilePath, "UTF-8"), "`r`n", "`n")
}
else {
    ; command line arguments for testing short sequences
    content := A_Args[1]
}

inKeySequence := false
keySequence := ""
lastKeySequence := ""
keystrokeTypeDelay := 100
keystrokeKeyDelay := 1000
keystrokeDelay := keystrokeTypeDelay

; make sure the mouse is not in the way as this will hide
; Emoji Keyboard for a moment when inserting to give focus
; back to the original app.
MouseGetPos(,&y)
MouseMove(A_ScreenWidth - 50, y, 0)
; SetKeyDelay(100, 100)
skipNewline := false
inKeySequence := false

loop parse, content, "" { ; empty delimiter "" parses character by character
    char := A_LoopField

    if (char = "``") { ; key sequence quotes
        if (inKeySequence) { ; it is the closing `
            keystrokeDelay := keystrokeKeyDelay
            justSending := false

            ; send key sequence
            if (RegExMatch(keySequence, "^#", &match)) {
                ; send lastKeySequence inserted
                if (keySequence = "#" && lastKeySequence != "") {
                    keySequence := lastKeySequence
                }
                ; just send
                else {
                    keySequence := SubStr(keySequence, 2)
                }
                lastKeySequence := ""
                justSending := true
            }
            ; insert key sequence
            else {
                justSending := false
                ; insert quotes ``
                SendText("````")
                ; go back to insert between quotes
                SendInput("{Left}")
                ; save key sequence for later sending by "#"
                lastKeySequence := keySequence
            }

            ; process sequence key by key
            while (keySequence != "") {
                if (RegExMatch(keySequence, "^{cls}", &match)) {
                    SendInput("^a{Del}")
                    skipNewline := 2
                }
                else if (RegExMatch(keySequence, "^{exit}", &match)) {
                    ExitApp
                }
                else if (RegExMatch(keySequence, "^{([dw]=?)\s*(\d+)(,(\d+))?}", &match)) {
                    if (match.1 = "w") {
                        if (justSending) {
                            Sleep(match.2 * 100)
                        }
                    }
                    else if (match.1 = "d") {
                        keystrokeDelay := match.2
                    }
                    else if (match.1 = "d=") {
                        keystrokeDelay := match.2
                        keystrokeTypeDelay := match.2
                        if (match.4 != "") {
                            keystrokeKeyDelay := match.4
                        }
                    }
                    keySequence := SubStr(keySequence, match.Len + 1)
                    continue
                }
                ; "{...}" a key sequence
                else if (RegExMatch(keySequence, "^{[^}]+}", &match)) {
                    if (justSending) {
                        seq := StrReplace(match.0, "´", "``")
                        if (RegExMatch(keySequence, "^{Loop,")) {
                            param := SubStr(match.0, 7, match.len - 7)
                            param := StrSplit(param, ",")
                            loop param[1] {
                                SendInput(param[2])
                                Sleep(keystrokeDelay)
                            }
                        }
                        else {
                            seq := match.0
                            seq := StrReplace(seq, "Shift+", "+")
                            seq := StrReplace(seq, "Ctrl+", "^")
                            seq := StrReplace(seq, "Alt+", "!")
                            seq := StrReplace(seq, "Win+", "#")
                            if (RegExMatch(seq, "^{([+^!#])(.+)}$", &modmatch)) {
                                if (StrLen(modmatch.2) > 2) {
                                    seq := modmatch.1 . "{" . modmatch.2 . "}"
                                }
                                else {
                                    seq := modmatch.1 . modmatch.2
                                }
                            }
                            SendInput(seq)
                            Sleep(keystrokeDelay)
                        }
                    }
                    else {
                        SendText(match.0)
                        Sleep(keystrokeDelay)
                    }
                }
                ; normal single letter key sequence
                else if (RegExMatch(keySequence, "^[^{}]+", &match)) {
                    loop parse, match.0, "" {
                        char := A_LoopField
                        if (justSending) {
                            SendInput(Format("{SC{:X}}", GetKeySC(char)))
                        }
                        else {
                            SendText(char)
                        }
                        Sleep(keystrokeDelay)
                    }
                }
                else {
                    SendText("Bugs happen: " . keySequence)
                    ExitApp
                }
                keySequence := SubStr(keySequence, match.Len + 1)
            }
            ; clear state
            keySequence := ""
            inKeySequence := false
            if (!justSending) {
                ; go out of `...`
                SendInput("{Right}")
            }
            keystrokeDelay := keystrokeTypeDelay
        }
        else { ; found an opening backtick, key sequence starts
            inKeySequence := true
        }
    }
    else if (inKeySequence) {
        ; Append the character to the key sequence buffer
        keySequence .= char
    }
    else { ; Normal text
        if (char = "`n") {
            if (skipNewline > 0) {
                skipNewline -= 1
            }
            else {
                SendInput("{Enter}")
            }
        }
        else {
            SendText(char)
        }
        Sleep(KeystrokeDelay)
    }
}
