#Requires AutoHotkey v2.0
#SingleInstance Force

; =========================================================
;  KeyFlip  -  Hebrew / English layout fixer
;  Typed in the wrong keyboard layout? Fix it without retyping.
;    * Fix-line hotkey  -> converts the whole current line
;    * Fix-word hotkey  -> converts only the last word
;    * If text is selected, converts exactly that selection.
;  The tray icon shows the current language (green EN / blue HE).
;  Right-click the tray icon to change hotkeys or options.
;  Settings persist in KeyFlip.ini next to this script.
; =========================================================

cfgFile := A_ScriptDir "\KeyFlip.ini"
enIcon  := A_ScriptDir "\en.ico"
heIcon  := A_ScriptDir "\he.ico"

englishKLID := "00000409"   ; US English layout id
hebrewKLID  := "0000040D"   ; Hebrew (standard) layout id

; ---- load settings (defaults used if the ini is missing) ----
lineHotkey        := IniRead(cfgFile, "Hotkeys", "line", "!SC029")    ; the single fix hotkey (default Alt + key-below-Esc)
switchLayoutAfter := (IniRead(cfgFile, "Options", "switchLayout", "1") = "1")

; Physical-key mapping: [ English (US) , Hebrew standard ]
pairs := [
  ["q","/"], ["w","'"], ["e","ק"], ["r","ר"], ["t","א"],
  ["y","ט"], ["u","ו"], ["i","ן"], ["o","ם"], ["p","פ"],
  ["a","ש"], ["s","ד"], ["d","ג"], ["f","כ"], ["g","ע"],
  ["h","י"], ["j","ח"], ["k","ל"], ["l","ך"], [";","ף"],
  ["'",","], ["z","ז"], ["x","ס"], ["c","ב"], ["v","ה"],
  ["b","נ"], ["n","מ"], ["m","צ"], [",","ת"], [".","ץ"],
  ["/","."]
]
eng2heb := Map()
heb2eng := Map()
for p in pairs {
  eng2heb[p[1]] := p[2]
  eng2heb[StrUpper(p[1])] := p[2]
  heb2eng[p[2]] := p[1]
}

; ---- bind the hotkey (from config) ----
try
  Hotkey lineHotkey, (*) => Convert("line")
catch
  MsgBox "Invalid hotkey in config: " lineHotkey, "KeyFlip"

BuildTray()
curLang := ""
UpdateLangIcon()
SetTimer UpdateLangIcon, 400

; =====================  functions  =======================

Convert(mode) {
  global eng2heb, heb2eng, switchLayoutAfter, englishKLID, hebrewKLID

  saved := ClipboardAll()
  A_Clipboard := ""
  Send "^c"
  if !ClipWait(0.4) {                       ; nothing selected -> auto-select
    Send (mode = "word") ? "+^{Left}" : "+{Home}"
    A_Clipboard := ""
    Send "^c"
    if !ClipWait(0.4) {
      A_Clipboard := saved
      ToggleLayout()        ; empty line / nothing to convert -> just flip the language
      return
    }
  }

  text := A_Clipboard
  if (text = "") {
    A_Clipboard := saved
    ToggleLayout()          ; nothing came through -> flip the language
    return
  }

  isHeb := IsMostlyHebrew(text)             ; which script is the gibberish to fix?
  m := isHeb ? heb2eng : eng2heb

  out := ""
  Loop Parse text
    out .= m.Has(A_LoopField) ? m[A_LoopField] : A_LoopField

  SendText out                              ; replaces the selected text
  Sleep 100
  A_Clipboard := saved                      ; restore the user's clipboard

  if switchLayoutAfter
    SetLayout(isHeb ? englishKLID : hebrewKLID)
}

IsMostlyHebrew(text) {
  heb := 0, lat := 0
  Loop Parse text {
    c := Ord(A_LoopField)
    if (c >= 0x0590 && c <= 0x05FF)
      heb += 1
    else if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A))
      lat += 1
  }
  return heb > lat
}

SetLayout(klid) {
  hwnd := WinExist("A")
  if !hwnd                                  ; no active window -> nothing to switch
    return
  hkl := DllCall("LoadKeyboardLayout", "Str", klid, "UInt", 1, "Ptr")
  try PostMessage(0x0050, 0, hkl, , "ahk_id " hwnd)   ; WM_INPUTLANGCHANGEREQUEST
}

ToggleLayout() {
  global englishKLID, hebrewKLID
  toEnglish := false
  if (hwnd := WinExist("A")) {
    tid := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt")
    hkl := DllCall("GetKeyboardLayout", "UInt", tid, "Ptr")
    toEnglish := (((hkl & 0xFFFF) & 0x3FF) = 0x0D)   ; currently Hebrew -> switch to English
  }
  SetLayout(toEnglish ? englishKLID : hebrewKLID)
}

UpdateLangIcon() {
  global curLang, enIcon, heIcon
  hwnd := WinExist("A")
  if !hwnd
    return
  tid  := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt")
  hkl  := DllCall("GetKeyboardLayout", "UInt", tid, "Ptr")
  prim := (hkl & 0xFFFF) & 0x3FF
  lang := (prim = 0x0D) ? "he" : "en"       ; 0x0D = Hebrew, else treat as English
  if (lang = curLang)
    return
  curLang := lang
  ico := (lang = "he") ? heIcon : enIcon
  if FileExist(ico)
    TraySetIcon(ico, , true)
  A_IconTip := "KeyFlip  -  now typing: " (lang = "he" ? "Hebrew" : "English")
}

BuildTray() {
  global lineHotkey, switchLayoutAfter
  t := A_TrayMenu
  t.Delete()
  t.Add("KeyFlip", NoOp),                            t.Disable("KeyFlip")
  t.Add()
  t.Add("Hotkey:  " PrettyHotkey(lineHotkey), NoOp), t.Disable("Hotkey:  " PrettyHotkey(lineHotkey))
  t.Add()
  t.Add("Change hotkey...", (*) => ChangeHotkey("line"))
  t.Add()
  t.Add("Switch language after fix", (*) => ToggleSwitch())
  if switchLayoutAfter
    t.Check("Switch language after fix")
  t.Add()
  t.Add("Reload", (*) => Reload())
  t.Add("Exit",   (*) => ExitApp())
}

NoOp(*) {
}

ToggleSwitch() {
  global switchLayoutAfter, cfgFile
  switchLayoutAfter := !switchLayoutAfter
  IniWrite(switchLayoutAfter ? "1" : "0", cfgFile, "Options", "switchLayout")
  BuildTray()
}

ChangeHotkey(which) {
  global cfgFile
  g := Gui("+AlwaysOnTop +ToolWindow", "Set hotkey")
  g.SetFont("s11", "Segoe UI")
  g.Add("Text", "w360",
      "Press the key combination for '" which "'.`n`n"
    . "Hold Ctrl / Alt / Shift / Win if you want, then press the main key.`n"
    . "Esc = cancel.")
  g.Show()

  combo := CaptureCombo()
  g.Destroy()

  if (combo = "" || combo = "CANCEL")
    return

  if (InStr(combo, "^") = 0 && InStr(combo, "!") = 0 && InStr(combo, "+") = 0 && InStr(combo, "#") = 0) {
    if (MsgBox("You picked a key with no modifier.`nYou won't be able to type that key normally.`n`nUse it anyway?",
               "KeyFlip", "YesNo Icon!") = "No")
      return
  }

  IniWrite(combo, cfgFile, "Hotkeys", (which = "line") ? "line" : "word")
  Reload()
}

CaptureCombo() {
  global g_capture
  g_capture := ""
  Suspend true                      ; disable our own hotkeys so the captured key can't fire them
  ih := InputHook()
  ih.KeyOpt("{All}", "NS")          ; Notify on every key + Suppress so nothing else reacts
  ih.OnKeyDown := CaptureKeyDown
  ih.Start()
  start := A_TickCount
  while (g_capture = "" && (A_TickCount - start) < 8000)
    Sleep 20
  ih.Stop()
  Suspend false                     ; re-enable hotkeys
  return g_capture
}

CaptureKeyDown(ih, vk, sc) {
  global g_capture
  static modVK := Map(0x10,1, 0x11,1, 0x12,1,           ; Shift/Ctrl/Alt (generic)
                      0xA0,1,0xA1,1,0xA2,1,0xA3,1,0xA4,1,0xA5,1,  ; L/R Shift/Ctrl/Alt
                      0x5B,1,0x5C,1,                    ; L/R Win
                      0x14,1,0x90,1,0x91,1)             ; Caps/Num/Scroll lock
  if modVK.Has(vk)                  ; ignore lone modifier presses, wait for the main key
    return
  m := ""
  if GetKeyState("Ctrl","P")
    m .= "^"
  if GetKeyState("Alt","P")
    m .= "!"
  if GetKeyState("Shift","P")
    m .= "+"
  if (GetKeyState("LWin","P") || GetKeyState("RWin","P"))
    m .= "#"
  if (sc = 1 && m = "") {           ; plain Escape = cancel
    g_capture := "CANCEL"
    return
  }
  g_capture := m "SC" Format("{:03X}", sc)
}

PrettyHotkey(h) {
  s := ""
  while (SubStr(h,1,1) ~= "[\^!+#]") {
    c := SubStr(h,1,1)
    s .= (c = "^") ? "Ctrl+" : (c = "!") ? "Alt+" : (c = "+") ? "Shift+" : "Win+"
    h := SubStr(h,2)
  }
  key := (h = "SC029") ? "[key below Esc]" : h
  return s key
}
