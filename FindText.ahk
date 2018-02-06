
/*
===========================================
  FindText - Capture screen image into text and then find it
  https://autohotkey.com/boards/viewtopic.php?f=6&t=17834

  Author  :  FeiYue
  Version :  5.6
  Date    :  2017-12-22

  Usage:
  1. Capture the image to text string.
  2. Test find the text string on full Screen.
  3. When test is successful, you may copy the code
     and paste it into your own script.
     Note: Copy the "FindText()" function and the following
     functions and paste it into your own script Just once.

===========================================
  Introduction of function parameters:

  returnArray := FindText( center point X, center point Y
    , Left and right offset to the center point W
    , Up and down offset to the center point H
    , Character "0" fault-tolerant in percentage
    , Character "_" fault-tolerant in percentage, text )

  parameters of the X,Y is the center of the coordinates,
  and the W,H is the offset distance to the center,
  So the search range is (X-W, Y-H)-->(X+W, Y+H).

  The fault-tolerant parameters allow the loss of specific characters.

  Text parameters can be a lot of text to find, separated by "|".

  return is a array, contains the [X,Y,W,H,Comment] results of Each Find.

===========================================
*/

#NoEnv
#SingleInstance Force
SetBatchLines, -1
CoordMode, Mouse
CoordMode, Pixel
CoordMode, ToolTip
SetWorkingDir, %A_ScriptDir%
Menu, Tray, Icon, Shell32.dll, 23
Menu, Tray, Add
Menu, Tray, Add, Main_Window
Menu, Tray, Default, Main_Window
Menu, Tray, Click, 1
; The capture range can be changed by adjusting the numbers
;----------------------------
  ww:=35, hh:=12
;----------------------------
nW:=2*ww+1, nH:=2*hh+1
Gosub, MakeCaptureWindow
Gosub, MakeMainWindow
Gosub, Load_ToolTip_Text
OnExit, savescr
Gosub, readscr
return


F12::    ; Hotkey --> Reload
SetTitleMatchMode, 2
SplitPath, A_ScriptName,,,, name
IfWinExist, %name%
{
  ControlSend, ahk_parent, {Ctrl Down}s{Ctrl Up}
  Sleep, 500
}
Reload
return


Load_ToolTip_Text:
ToolTip_Text=
(LTrim
Capture   = Initiate Image Capture Sequence
Test      = Test Results of Code
Copy      = Copy Code to Clipboard
AddFunc   = Additional FindText() in Copy
U         = Cut the Upper Edge by 1
U3        = Cut the Upper Edge by 3
L         = Cut the Left Edge by 1
L3        = Cut the Left Edge by 3
R         = Cut the Right Edge by 1
R3        = Cut the Right Edge by 3
D         = Cut the Lower Edge by 1
D3        = Cut the Lower Edge by 3
Auto      = Automatic Cutting Edge`r`nOnly after Color2Two or Gray2Two
Similar   = Adjust color similarity as Equivalent to The Selected Color
SelCol    = Selected Image Color which Determines Black or Pixel White Conversion (Hex of Color)
Gray      = Grayscale Threshold which Determines Black or White Pixel Conversion (0-255)
Color2Two = Converts Image Pixels from Color to Black or White`r`nDepending on Selection Color and Sensitivity
Gray2Two  = Converts Image Pixels from Grays to Black or White`r`nDepending on Gray Threshold
Modify    = Allows for Pixel Cleanup of Black and White Image`r`nOnly After Gray2Two or Color2Two
Reset     = Reset to Original Captured Image
Invert    = Invert Images Black and White`r`nOnly after Color2Two or Gray2Two
Comment   = Optional Comment used to Label Code ( Within <> )
OK        = Create New FindText Code for Testing
Append    = Append Another FindText Search Text into Previously Generated Code
Close     = Close the Window Don't Do Anything
)
return

readscr:
f=%A_Temp%\~scr.tmp
FileRead, s, %f%
GuiControl, Main:, scr, %s%
s=
return

savescr:
f=%A_Temp%\~scr.tmp
GuiControlGet, s, Main:, scr
FileDelete, %f%
FileAppend, %s%, %f%
ExitApp

Main_Window:
Gui, Main:Show, Center
return

MakeMainWindow:
Gui, Main:Default
Gui, +AlwaysOnTop +HwndMain_ID
Gui, Margin, 15, 15
Gui, Color, DDEEFF
Gui, Font, s6 bold, Verdana
Gui, Add, Edit, xm w660 r25 vMyEdit -Wrap -VScroll
Gui, Font, s12 norm, Verdana
Gui, Add, Button, w220 gMainRun, Capture
Gui, Add, Button, x+0 wp gMainRun, Test
Gui, Add, Button, x+0 wp gMainRun Section, Copy
Gui, Font, s10
Gui, Add, Text, xm, Click Text String to See ASCII Search Text in the Above
Gui, Add, Checkbox, xs yp w220 r1 -Wrap Checked vAddFunc, Additional FindText() in Copy
Gui, Font, s12 cBlue, Verdana
Gui, Add, Edit, xm w660 h350 vscr Hwndhscr -Wrap HScroll
Gui, Show,, Capture Image To Text And Find Text Tool
;---------------------------------------
OnMessage(0x100, "EditEvents1")  ; WM_KEYDOWN
OnMessage(0x201, "EditEvents2")  ; WM_LBUTTONDOWN
OnMessage(0x200, "WM_MOUSEMOVE") ; Show ToolTip
return

EditEvents1()
{
  ListLines, Off
  if (A_Gui="Main") and (A_GuiControl="scr")
    SetTimer, ShowText, -100
}

EditEvents2()
{
  ListLines, Off
  if (A_Gui="Capture")
    WM_LBUTTONDOWN()
  else
    EditEvents1()
}

ShowText:
ListLines, Off
Critical
ControlGet, i, CurrentLine,,, ahk_id %hscr%
ControlGet, s, Line, %i%,, ahk_id %hscr%
s := ASCII(s)
GuiControl, Main:, MyEdit, % Trim(s,"`n")
return

MainRun:
k:=A_GuiControl
WinMinimize
Gui, Hide
DetectHiddenWindows, Off
WinWaitClose, ahk_id %Main_ID%
if IsLabel(k)
  Gosub, %k%
Gui, Main:Show
GuiControl, Main:Focus, scr
return

Copy:
GuiControlGet, s,, scr
GuiControlGet, AddFunc
if AddFunc != 1
  s:=RegExReplace(s,"\n\K[\s;=]+ Copy The[\s\S]*")
Clipboard:=StrReplace(s,"`n","`r`n")
s=
return

Capture:
Gui, Mini:Default
Gui, +LastFound +AlwaysOnTop -Caption +ToolWindow +E0x08000000
WinSet, Transparent, 100
Gui, Color, Red
Gui, Show, Hide w%nW% h%nH%
;------------------------------
Hotkey, $*LButton, _LButton_Off, On
ListLines, Off
Loop {
  MouseGetPos, px, py
  if GetKeyState("LButton","P")
    Break
  Gui, Show, % "NA x" (px-ww) " y" (py-hh)
  ToolTip, % "The Mouse Pos : " px "," py
    . "`nPlease Move and Click LButton"
  Sleep, 20
}
KeyWait, LButton
Gui, Color, White
Loop {
  MouseGetPos, x, y
  if Abs(px-x)+Abs(py-y)>100
    Break
  Gui, Show, % "NA x" (x-ww) " y" (y-hh)
  ToolTip, Please Move Mouse > 100 Pixels
  Sleep, 20
}
ToolTip
ListLines, On
Hotkey, $*LButton, Off
Gui, Destroy
WinWaitClose
cors:=getc(px,py,ww,hh)
Gui, Capture:Default
GuiControl,, SelCol
GuiControl,, Gray
GuiControl,, Modify, % Modify:=0
GuiControl, Focus, Gray
Gosub, Reset
Gui, Show, Center
DetectHiddenWindows, Off
WinWaitClose, ahk_id %Capture_ID%
_LButton_Off:
return

WM_LBUTTONDOWN()
{
  global
  ListLines, Off
  MouseGetPos,,,, mclass
  if !InStr(mclass,"progress")
    return
  MouseGetPos,,,, mid, 2
  For k,v in C_
    if (v=mid)
    {
      if (Modify and bg!="")
      {
        c:=cc[k], cc[k]:=c="0" ? "_" : c="_" ? "0" : c
        c:=c="0" ? "White" : c="_" ? "Black" : WindowColor
        Gosub, SetColor
      }
      else
        GuiControl, Capture:, SelCol, % cors[k]
      return
    }
}

getc(px, py, ww, hh)
{
  xywh2xywh(px-ww,py-hh,2*ww+1,2*hh+1,x,y,w,h)
  if (w<1 or h<1)
    return, 0
  bch:=A_BatchLines
  SetBatchLines, -1
  ;--------------------------------------
  GetBitsFromScreen(x,y,w,h,Scan0,Stride,bits)
  ;--------------------------------------
  cors:=[], k:=0, nW:=2*ww+1, nH:=2*hh+1
  ListLines, Off
  fmt:=A_FormatInteger
  SetFormat, IntegerFast, H
  Loop, %nH% {
    j:=py-hh-y+A_Index-1
    Loop, %nW% {
      i:=px-ww-x+A_Index-1, k++
      if (i>=0 and i<w and j>=0 and j<h)
        c:=NumGet(Scan0+0,i*4+j*Stride,"uint")
          , cors[k]:="0x" . SubStr(0x1000000|c,-5)
      else
        cors[k]:="0xFFFFFF"
    }
  }
  SetFormat, IntegerFast, %fmt%
  ListLines, On
  cors.left:=Abs(px-ww-x)
  cors.right:=Abs(px+ww-(x+w-1))
  cors.up:=Abs(py-hh-y)
  cors.down:=Abs(py+hh-(y+h-1))
  SetBatchLines, %bch%
  return, cors
}

Test:
GuiControlGet, s, Main:, scr
s:="`n#NoEnv`nMenu, Tray, Click, 1`n"
  . "Gui, _ok_:Show, Hide, _ok_`n"
  . s "`nExitApp`n#SingleInstance off`n"
if !A_IsCompiled
{
  Exec(s)
  DetectHiddenWindows, On
  WinWait, _ok_ ahk_class AutoHotkeyGUI,, 3
  WinWaitClose, _ok_ ahk_class AutoHotkeyGUI,, 3
}
else
{
  t1:=A_TickCount
  RegExMatch(s,"=""\K[^\n]+?\d\.[\w+/]{3,}",Text)
  ok:=FindText(0, 0, 150000, 150000, 0, 0, Text)
  X:=ok.1.1, Y:=ok.1.2, W:=ok.1.3, H:=ok.1.4, Comment:=ok.1.5, X+=W//2, Y+=H//2
  MsgBox, 4096,, % "Time:`t" (A_TickCount-t1) " ms`n`n"
    . "Pos:`t" X ", " Y "`n`n"
    . "Result:`t" (ok ? "Success !":"Failed !"), 3
  MouseMove, X, Y
}
return

Exec(s)
{
  Ahk:=A_IsCompiled ? A_ScriptDir "\AutoHotkey.exe":A_AhkPath
  s:=RegExReplace(s, "\R", "`r`n")
  Try {
    oExec:=ComObjCreate("WScript.Shell").Exec(Ahk " /r *")
    oExec.StdIn.Write(s)
    oExec.StdIn.Close()
  }
  catch {
    s:="`r`nFileDelete, %A_ScriptFullPath%`r`n" . s
    f:=A_Temp "\~test.tmp"
    FileDelete, %f%
    FileAppend, %s%, %f%
    Run, %Ahk% /r "%f%"
  }
}

MakeCaptureWindow:
WindowColor:="0xCCDDEE"
Gui, Capture:Default
Gui, +LastFound +AlwaysOnTop +ToolWindow +HwndCapture_ID
Gui, Margin, 15, 15
Gui, Color, %WindowColor%
Gui, Font, s14, Verdana
ListLines, Off
w:=800//nW+1, h:=(A_ScreenHeight-300)//nH+1, w:=h<w ? h:w
Loop, % nH*nW {
  j:=A_Index=1 ? "" : Mod(A_Index,nW)=1 ? "xm y+-1" : "x+-1"
  Gui, Add, Progress, w%w% h%w% %j% -Theme
}
ListLines, On
Gui, Add, Button, xm+95  w45 gUpCut Section, U
Gui, Add, Button, x+0    wp gUpCut3, U3
Gui, Add, Text,   xm+310 yp+6 Section, Color Similarity  0
Gui, Add, Slider
  , x+0 w250 vSimilar Page1 NoTicks ToolTip Center, 100
Gui, Add, Text,   x+0, 100
Gui, Add, Button, xm     w45 gLeftCut, L
Gui, Add, Button, x+0    wp gLeftCut3, L3
Gui, Add, Button, x+15   w70 gRun, Auto
Gui, Add, Button, x+15   w45 gRightCut, R
Gui, Add, Button, x+0    wp gRightCut3, R3
Gui, Add, Text,   xs     w160 yp, Selected  Color
Gui, Add, Edit,   x+15   w140 vSelCol
Gui, Add, Button, x+15   w150 gRun, Color2Two
Gui, Add, Button, xm+95  w45 gDownCut, D
Gui, Add, Button, x+0    wp gDownCut3, D3
Gui, Add, Text,   xs     w160 yp, Gray Threshold
Gui, Add, Edit,   x+15   w140 vGray
Gui, Add, Button, x+15   w150 gRun Default, Gray2Two
Gui, Add, Checkbox, xm   y+21 gRun vModify, Modify
Gui, Add, Button, x+5    yp-6 gRun, Reset
Gui, Add, Button, x+15   gRun, Invert
Gui, Add, Text,   x+15   yp+6, Add Comment
Gui, Add, Edit,   x+5    w100 vComment
Gui, Add, Button, x+15   w85 yp-6 gRun, OK
Gui, Add, Button, x+10   gRun, Append
Gui, Add, Button, x+10   gCancel, Close
Gui, Show, Hide, Capture Image To Text
WinGet, s, ControlListHwnd
C_:=StrSplit(s,"`n"), s:=""
return

Run:
Critical
k:=A_GuiControl
Gui, +OwnDialogs
if IsLabel(k)
  Goto, %k%
return

Modify:
GuiControlGet, Modify
return

SetColor:
c:=c="White" ? 0xFFFFFF : c="Black" ? 0x000000
  : ((c&0xFF)<<16)|(c&0xFF00)|((c&0xFF0000)>>16)
SendMessage, 0x2001, 0, c,, % "ahk_id " . C_[k]
return

Reset:
if !IsObject(cc)
  cc:=[], gc:=[], pp:=[]
left:=right:=up:=down:=k:=0, bg:=""
Loop, % nH*nW {
  cc[++k]:=1, c:=cors[k], gc[k]:=(((c>>16)&0xFF)*299
    +((c>>8)&0xFF)*587+(c&0xFF)*114)//1000
  Gosub, SetColor
}
Loop, % cors.left
  Gosub, LeftCut
Loop, % cors.right
  Gosub, RightCut
Loop, % cors.up
  Gosub, UpCut
Loop, % cors.down
  Gosub, DownCut
return

Color2Two:
GuiControlGet, Similar
GuiControlGet, r,, SelCol
if r=
{
  MsgBox, 4096, Tip
    , `n  Please Select a Color First !  `n, 1
  return
}
Similar:=Round(Similar/100,2), n:=Floor(255*3*(1-Similar))
color:=r "@" Similar, k:=i:=0
rr:=(r>>16)&0xFF, gg:=(r>>8)&0xFF, bb:=r&0xFF
Loop, % nH*nW {
  if (cc[++k]="")
    Continue
  c:=cors[k], r:=(c>>16)&0xFF, g:=(c>>8)&0xFF, b:=c&0xFF
  if Abs(r-rr)+Abs(g-gg)+Abs(b-bb)<=n
    cc[k]:="0", c:="Black", i++
  else
    cc[k]:="_", c:="White", i--
  Gosub, SetColor
}
bg:=i>0 ? "0":"_"
return

Gray2Two:
GuiControl, Focus, Gray
GuiControlGet, Threshold,, Gray
if Threshold=
{
  Loop, 256
    pp[A_Index-1]:=0
  Loop, % nH*nW
    if (cc[A_Index]!="")
      pp[gc[A_Index]]++
  IP:=IS:=0
  Loop, 256
    k:=A_Index-1, IP+=k*pp[k], IS+=pp[k]
  NewThreshold:=Floor(IP/IS)
  Loop, 20 {
    Threshold:=NewThreshold
    IP1:=IS1:=0
    Loop, % Threshold+1
      k:=A_Index-1, IP1+=k*pp[k], IS1+=pp[k]
    IP2:=IP-IP1, IS2:=IS-IS1
    if (IS1!=0 and IS2!=0)
      NewThreshold:=Floor((IP1/IS1+IP2/IS2)/2)
    if (NewThreshold=Threshold)
      Break
  }
  GuiControl,, Gray, %Threshold%
}
color:="*" Threshold, k:=i:=0
Loop, % nH*nW {
  if (cc[++k]="")
    Continue
  if (gc[k]<Threshold+1)
    cc[k]:="0", c:="Black", i++
  else
    cc[k]:="_", c:="White", i--
  Gosub, SetColor
}
bg:=i>0 ? "0":"_"
return

gui_del:
cc[k]:="", c:=WindowColor
Gosub, SetColor
return

LeftCut3:
Loop, 3
  Gosub, LeftCut
return

LeftCut:
if (left+right>=nW)
  return
left++, k:=left
Loop, %nH% {
  Gosub, gui_del
  k+=nW
}
return

RightCut3:
Loop, 3
  Gosub, RightCut
return

RightCut:
if (left+right>=nW)
  return
right++, k:=nW+1-right
Loop, %nH% {
  Gosub, gui_del
  k+=nW
}
return

UpCut3:
Loop, 3
  Gosub, UpCut
return

UpCut:
if (up+down>=nH)
  return
up++, k:=(up-1)*nW
Loop, %nW% {
  k++
  Gosub, gui_del
}
return

DownCut3:
Loop, 3
  Gosub, DownCut
return

DownCut:
if (up+down>=nH)
  return
down++, k:=(nH-down)*nW
Loop, %nW% {
  k++
  Gosub, gui_del
}
return

getwz:
wz=
if bg=
  return
ListLines, Off
k:=0
Loop, %nH% {
  v=
  Loop, %nW%
    v.=cc[++k]
  wz.=v="" ? "" : v "`n"
}
ListLines, On
return

Auto:
Gosub, getwz
if wz=
{
  MsgBox, 4096, Tip
    , `nPlease Click Color2Two or Gray2Two First !, 1
  return
}
While InStr(wz,bg) {
  if (wz~="^" bg "+\n")
  {
    wz:=RegExReplace(wz,"^" bg "+\n")
    Gosub, UpCut
  }
  else if !(wz~="m`n)[^\n" bg "]$")
  {
    wz:=RegExReplace(wz,"m`n)" bg "$")
    Gosub, RightCut
  }
  else if (wz~="\n" bg "+\n$")
  {
    wz:=RegExReplace(wz,"\n\K" bg "+\n$")
    Gosub, DownCut
  }
  else if !(wz~="m`n)^[^\n" bg "]")
  {
    wz:=RegExReplace(wz,"m`n)^" bg)
    Gosub, LeftCut
  }
  else Break
}
wz=
return

OK:
Append:
Invert:
Gosub, getwz
if wz=
{
  MsgBox, 4096, Tip
    , `nPlease Click Color2Two or Gray2Two First !, 1
  return
}
if A_ThisLabel=Invert
{
  wz:="", k:=0, bg:=bg="0" ? "_":"0"
  color:=InStr(color,"-") ? StrReplace(color,"-"):"-" color
  Loop, % nH*nW
    if (c:=cc[++k])!=""
    {
      cc[k]:=c="0" ? "_":"0", c:=c="0" ? "White":"Black"
      Gosub, SetColor
    }
  return
}
if InStr(color,"@")
{
  StringSplit, r, color, @
  t:=InStr(r1,"-") ? "-":"", r1:=StrReplace(r1,"-")
  k:=i:=j:=0
  Loop, % nH*nW {
    if (cc[++k]="")
      Continue
    i++
    if (cors[k]=r1)
    {
      j:=i
      Break
    }
  }
  if (j=0)
  {
    MsgBox, 4096, Tip
      , Please select the reference color again !, 1
    return
  }
  color:=t . j . "@" . r2
}
if A_ThisLabel=Append
{
  add(towz(color,wz))
  MsgBox, 4096, Tip
    , Success! you can Reset to Append more!, 1
  return
}
Gui, Hide
px1:=px-ww+left+(nW-left-right)//2
py1:=py-hh+up+(nH-up-down)//2
s:=StrReplace(towz(color,wz), "Text.=", "Text:=")
s=
(

t1:=A_TickCount

%s%

if (ok:=FindText(%px1%, %py1%, 150000, 150000, 0, 0, Text))
{
  CoordMode, Mouse
  X:=ok.1.1, Y:=ok.1.2, W:=ok.1.3, H:=ok.1.4, Comment:=ok.1.5, X+=W//2, Y+=H//2
  ; Click, `%X`%, `%Y`%
}

MsgBox, 4096,, `% "Time:``t" (A_TickCount-t1) " ms``n``n"
  . "Pos:``t" X ", " Y "``n``n"
  . "Result:``t" (ok ? "Success !":"Failed !"), 3
MouseMove, X, Y

)
if !A_IsCompiled
{
  FileRead, fs, %A_ScriptFullPath%
  fs:=SubStr(fs,fs~="i)\n[;=]+ Copy The")
}
GuiControl, Main:, scr, %s%`n%fs%
s:=wz:=fs:=""
return

towz(color,wz)
{
  global Comment
  GuiControlGet, Comment
  SetFormat, IntegerFast, d
  wz:=StrReplace(StrReplace(wz,"0","1"),"_","0")
  wz:=InStr(wz,"`n")-1 . "." . bit2base64(wz)
  return, "Text.=""|<" Comment ">" color "$" wz """"
}

add(s)
{
  global hscr
  s:=RegExReplace("`n" s "`n","\R","`r`n")
  ControlGet, i, CurrentCol,,, ahk_id %hscr%
  if i>1
    ControlSend,, {Home}{Down}, ahk_id %hscr%
  Control, EditPaste, %s%,, ahk_id %hscr%
}

WM_MOUSEMOVE()
{
  ListLines, Off
  static CurrControl, PrevControl
  CurrControl := A_GuiControl
  if (CurrControl!=PrevControl)
  {
    PrevControl := CurrControl
    ToolTip
    if CurrControl !=
      SetTimer, DisplayToolTip, -1000
  }
  return

  DisplayToolTip:
  ListLines, Off
  k:="ToolTip_Text"
  TT_:=RegExMatch(%k%,"m`n)^" . CurrControl
    . "\K\s*=.*", r) ? Trim(r,"`t =") : ""
  MouseGetPos,,, k
  WinGetClass, k, ahk_id %k%
  if k = AutoHotkeyGUI
  {
    ToolTip, %TT_%
    SetTimer, RemoveToolTip, -5000
  }
  return

  RemoveToolTip:
  ToolTip
  return
}


;===== Copy The Following Functions To Your Own Code Just once =====


; Note: parameters of the X,Y is the center of the coordinates,
; and the W,H is the offset distance to the center,
; So the search range is (X-W, Y-H)-->(X+W, Y+H).
; err1 is the character "0" fault-tolerant in percentage.
; err0 is the character "_" fault-tolerant in percentage.
; Text can be a lot of text to find, separated by "|".
; ruturn is a array, contains the [X,Y,W,H,Comment] results of Each Find.

FindText(x,y,w,h,err1,err0,text)
{
  xywh2xywh(x-w,y-h,2*w+1,2*h+1,x,y,w,h)
  if (w<1 or h<1)
    return, 0
  bch:=A_BatchLines
  SetBatchLines, -1
  ;--------------------------------------
  GetBitsFromScreen(x,y,w,h,Scan0,Stride,bits)
  ;--------------------------------------
  sx:=0, sy:=0, sw:=w, sh:=h, arr:=[]
  Loop, Parse, text, |
  {
    v:=A_LoopField
    IfNotInString, v, $, Continue
    Comment:="", e1:=err1, e0:=err0
    ; You Can Add Comment Text within The <>
    if RegExMatch(v,"<([^>]*)>",r)
      v:=StrReplace(v,r), Comment:=Trim(r1)
    ; You can Add two fault-tolerant in the [], separated by commas
    if RegExMatch(v,"\[([^\]]*)]",r)
    {
      v:=StrReplace(v,r), r1.=","
      StringSplit, r, r1, `,
      e1:=r1, e0:=r2
    }
    StringSplit, r, v, $
    color:=r1, v:=r2
    StringSplit, r, v, .
    w1:=r1, v:=base64tobit(r2), h1:=StrLen(v)//w1
    if (r0<2 or h1<1 or w1>sw or h1>sh or StrLen(v)!=w1*h1)
      Continue
    ;--------------------------------------------
    if InStr(color,"-")
    {
      r:=e1, e1:=e0, e0:=r, v:=StrReplace(v,"1","_")
      v:=StrReplace(StrReplace(v,"0","1"),"_","0")
      color:=StrReplace(color,"-")
    }
    mode:=InStr(color,"*") ? 1:0
    color:=StrReplace(color,"*") . "@"
    StringSplit, r, color, @
    color:=mode=1 ? r1 : ((r1-1)//w1)*Stride+Mod(r1-1,w1)*4
    n:=Round(r2,2)+(!r2), n:=Floor(255*3*(1-n))
    StrReplace(v,"1","",len1), len0:=StrLen(v)-len1
    VarSetCapacity(allpos, 1024*4, 0), k:=StrLen(v)*4
    VarSetCapacity(s1, k, 0), VarSetCapacity(s0, k, 0)
    ;--------------------------------------------
    if (ok:=PicFind(mode,color,n,Scan0,Stride,sx,sy,sw,sh
      ,v,s1,s0,Round(len1*e1),Round(len0*e0),w1,h1,allpos))
      or (err1=0 and err0=0
      and (ok:=PicFind(mode,color,n,Scan0,Stride,sx,sy,sw,sh
      ,v,s1,s0,Round(len1*0.05),Round(len0*0.05),w1,h1,allpos)))
    {
      Loop, % ok
        pos:=NumGet(allpos, 4*(A_Index-1), "uint")
        , rx:=(pos&0xFFFF)+x, ry:=(pos>>16)+y
        , arr.Push( [rx,ry,w1,h1,Comment] )
    }
  }
  SetBatchLines, %bch%
  return, arr.MaxIndex() ? arr:0
}

PicFind(mode, color, n, Scan0, Stride, sx, sy, sw, sh
  , ByRef text, ByRef s1, ByRef s0
  , err1, err0, w1, h1, ByRef allpos)
{
  static MyFunc
  if !MyFunc
  {
    x32:="5589E55383EC50C745E8000000008B45242B454083C0018"
    . "945C88B45282B454483C0018945C48B45200FAF45188B551CC"
    . "1E20201D08945C0C745CC000000008B45CC8945D08B45D0894"
    . "5F8C745EC00000000EB78C745F000000000EB638B45EC0FAF4"
    . "5188B55F0C1E20201D08945BC8B45F88D50018955F889C28B4"
    . "52C01D00FB6003C31751C8B45D08D50018955D08D148500000"
    . "0008B453001C28B45BC8902EB1A8B45CC8D50018955CC8D148"
    . "5000000008B453401C28B45BC89028345F0018B45F03B45407"
    . "C958345EC018B45EC3B45447C808B45D03945CC0F4D45CC894"
    . "5B8837D08000F854D020000C745EC00000000E930020000C74"
    . "5F000000000E9140200008B45EC0FAF45188B55F0C1E20201C"
    . "28B45C001D08945F88B45388945D88B453C8945D48B55F88B4"
    . "50C01D08945BC8B45BC83C00289C28B451401D00FB6000FB6C"
    . "08945B48B45BC83C00189C28B451401D00FB6000FB6C08945B"
    . "08B55BC8B451401D00FB6000FB6C08945ACC745F400000000E"
    . "94C0100008B45F43B45D00F8D9A0000008B45F48D148500000"
    . "0008B453001D08B108B45F801D08945BC8B45BC83C00289C28"
    . "B451401D00FB6000FB6C02B45B48945E48B45BC83C00189C28"
    . "B451401D00FB6000FB6C02B45B08945E08B55BC8B451401D00"
    . "FB6000FB6C02B45AC8945DC837DE4007903F75DE4837DE0007"
    . "903F75DE0837DDC007903F75DDC8B55E48B45E001C28B45DC0"
    . "1D03B45107E0E836DD801837DD8000F88EF0000008B45F43B4"
    . "5CC0F8D960000008B45F48D1485000000008B453401D08B108"
    . "B45F801D08945BC8B45BC83C00289C28B451401D00FB6000FB"
    . "6C02B45B48945E48B45BC83C00189C28B451401D00FB6000FB"
    . "6C02B45B08945E08B55BC8B451401D00FB6000FB6C02B45AC8"
    . "945DC837DE4007903F75DE4837DE0007903F75DE0837DDC007"
    . "903F75DDC8B55E48B45E001C28B45DC01D03B45107F0A836DD"
    . "401837DD40078508345F4018B45F43B45B80F8CA8FEFFFF8B4"
    . "5E88D50018955E88D1485000000008B454801D08B4D208B55E"
    . "C01CA89D3C1E3108B4D1C8B55F001CA09DA8910817DE8FF030"
    . "0000F8FFE010000EB0490EB01908345F0018B45F03B45C80F8"
    . "CE0FDFFFF8345EC018B45EC3B45C40F8CC4FDFFFFE9D701000"
    . "08B450C83C00169C0E803000089450CC745EC00000000E98D0"
    . "00000C745F000000000EB788B45EC0FAF45188B55F0C1E2020"
    . "1C28B45C001D08945F88B45F883C00389C28B451401D08B55F"
    . "883C20289D18B551401CA0FB6120FB6D269CA2B0100008B55F"
    . "883C20189D38B551401DA0FB6120FB6D269D24B0200008D1C1"
    . "18B4DF88B551401CA0FB6120FB6D26BD27201DA3B550C0F9CC"
    . "288108345F0018B45F03B45247C808345EC018B45EC3B45280"
    . "F8C67FFFFFF8345C003C745EC00000000E901010000C745F00"
    . "0000000E9E50000008B45EC0FAF45188B55F0C1E20201C28B4"
    . "5C001D08945F88B45388945D88B453C8945D4C745F40000000"
    . "0EB708B45F43B45D07D2E8B45F48D1485000000008B453001D"
    . "08B108B45F801D089C28B451401D00FB6003C01740A836DD80"
    . "1837DD800787B8B45F43B45CC7D2E8B45F48D1485000000008"
    . "B453401D08B108B45F801D089C28B451401D00FB60084C0740"
    . "A836DD401837DD40078488345F4018B45F43B45B87C888B45E"
    . "88D50018955E88D1485000000008B454801D08B4D208B55EC0"
    . "1CA89D3C1E3108B4D1C8B55F001CA09DA8910817DE8FF03000"
    . "07F2BEB0490EB01908345F0018B45F03B45C80F8C0FFFFFFF8"
    . "345EC018B45EC3B45C40F8CF3FEFFFFEB0490EB01908B45E88"
    . "3C4505B5DC244009090"
    x64:="554889E54883EC50894D10895518448945204C894D28C74"
    . "5EC000000008B45482B858000000083C0018945CC8B45502B8"
    . "58800000083C0018945C88B45400FAF45308B5538C1E20201D"
    . "08945C4C745D0000000008B45D08945D48B45D48945FCC745F"
    . "000000000E988000000C745F400000000EB708B45F00FAF453"
    . "08B55F4C1E20201D08945C08B45FC8D50018955FC4863D0488"
    . "B45584801D00FB6003C3175218B45D48D50018955D44898488"
    . "D148500000000488B45604801C28B45C08902EB1F8B45D08D5"
    . "0018955D04898488D148500000000488B45684801C28B45C08"
    . "9028345F4018B45F43B85800000007C858345F0018B45F03B8"
    . "5880000000F8C69FFFFFF8B45D43945D00F4D45D08945BC837"
    . "D10000F8582020000C745F000000000E965020000C745F4000"
    . "00000E9490200008B45F00FAF45308B55F4C1E20201C28B45C"
    . "401D08945FC8B45708945DC8B45788945D88B55FC8B451801D"
    . "08945C08B45C083C0024863D0488B45284801D00FB6000FB6C"
    . "08945B88B45C083C0014863D0488B45284801D00FB6000FB6C"
    . "08945B48B45C04863D0488B45284801D00FB6000FB6C08945B"
    . "0C745F800000000E96C0100008B45F83B45D40F8DAA0000008"
    . "B45F84898488D148500000000488B45604801D08B108B45FC0"
    . "1D08945C08B45C083C0024863D0488B45284801D00FB6000FB"
    . "6C02B45B88945E88B45C083C0014863D0488B45284801D00FB"
    . "6000FB6C02B45B48945E48B45C04863D0488B45284801D00FB"
    . "6000FB6C02B45B08945E0837DE8007903F75DE8837DE400790"
    . "3F75DE4837DE0007903F75DE08B55E88B45E401C28B45E001D"
    . "03B45207E0E836DDC01837DDC000F88090100008B45F83B45D"
    . "00F8DA60000008B45F84898488D148500000000488B4568480"
    . "1D08B108B45FC01D08945C08B45C083C0024863D0488B45284"
    . "801D00FB6000FB6C02B45B88945E88B45C083C0014863D0488"
    . "B45284801D00FB6000FB6C02B45B48945E48B45C04863D0488"
    . "B45284801D00FB6000FB6C02B45B08945E0837DE8007903F75"
    . "DE8837DE4007903F75DE4837DE0007903F75DE08B55E88B45E"
    . "401C28B45E001D03B45207F0A836DD801837DD800785A8345F"
    . "8018B45F83B45BC0F8C88FEFFFF8B45EC8D50018955EC48984"
    . "88D148500000000488B85900000004801D08B4D408B55F001C"
    . "AC1E2104189D08B4D388B55F401CA4409C28910817DECFF030"
    . "0000F8F3A020000EB0490EB01908345F4018B45F43B45CC0F8"
    . "CABFDFFFF8345F0018B45F03B45C80F8C8FFDFFFFE91302000"
    . "08B451883C00169C0E8030000894518C745F000000000E9A40"
    . "00000C745F400000000E9880000008B45F00FAF45308B55F4C"
    . "1E20201C28B45C401D08945FC8B45FC83C0034863D0488B452"
    . "84801D08B55FC83C2024863CA488B55284801CA0FB6120FB6D"
    . "269CA2B0100008B55FC83C2014C63C2488B55284C01C20FB61"
    . "20FB6D269D24B020000448D04118B55FC4863CA488B5528480"
    . "1CA0FB6120FB6D26BD2724401C23B55180F9CC288108345F40"
    . "18B45F43B45480F8C6CFFFFFF8345F0018B45F03B45500F8C5"
    . "0FFFFFF8345C403C745F000000000E926010000C745F400000"
    . "000E90A0100008B45F00FAF45308B55F4C1E20201C28B45C40"
    . "1D08945FC8B45708945DC8B45788945D8C745F800000000E98"
    . "40000008B45F83B45D47D3A8B45F84898488D1485000000004"
    . "88B45604801D08B108B45FC01D04863D0488B45284801D00FB"
    . "6003C01740E836DDC01837DDC000F88910000008B45F83B45D"
    . "07D368B45F84898488D148500000000488B45684801D08B108"
    . "B45FC01D04863D0488B45284801D00FB60084C0740A836DD80"
    . "1837DD80078568345F8018B45F83B45BC0F8C70FFFFFF8B45E"
    . "C8D50018955EC4898488D148500000000488B8590000000480"
    . "1D08B4D408B55F001CAC1E2104189D08B4D388B55F401CA440"
    . "9C28910817DECFF0300007F2BEB0490EB01908345F4018B45F"
    . "43B45CC0F8CEAFEFFFF8345F0018B45F03B45C80F8CCEFEFFF"
    . "FEB0490EB01908B45EC4883C4505DC39090909090909090"
    MCode(MyFunc, A_PtrSize=8 ? x64:x32)
  }
  return, DllCall(&MyFunc, "int",mode
    , "uint",color, "int",n, "ptr",Scan0, "int",Stride
    , "int",sx, "int",sy, "int",sw, "int",sh
    , "AStr",text, "ptr",&s1, "ptr",&s0
    , "int",err1, "int",err0, "int",w1, "int",h1, "ptr",&allpos)
}

xywh2xywh(x1,y1,w1,h1,ByRef x,ByRef y,ByRef w,ByRef h)
{
  SysGet, zx, 76
  SysGet, zy, 77
  SysGet, zw, 78
  SysGet, zh, 79
  left:=x1, right:=x1+w1-1, up:=y1, down:=y1+h1-1
  left:=left<zx ? zx:left, right:=right>zx+zw-1 ? zx+zw-1:right
  up:=up<zy ? zy:up, down:=down>zy+zh-1 ? zy+zh-1:down
  x:=left, y:=up, w:=right-left+1, h:=down-up+1
}

GetBitsFromScreen(x,y,w,h,ByRef Scan0,ByRef Stride,ByRef bits)
{
  VarSetCapacity(bits,w*h*4,0), bpp:=32
  Scan0:=&bits, Stride:=((w*bpp+31)//32)*4
  Ptr:=A_PtrSize ? "UPtr" : "UInt", PtrP:=Ptr . "*"
  win:=DllCall("GetDesktopWindow", Ptr)
  hDC:=DllCall("GetWindowDC", Ptr,win, Ptr)
  mDC:=DllCall("CreateCompatibleDC", Ptr,hDC, Ptr)
  ;-------------------------
  VarSetCapacity(bi, 40, 0), NumPut(40, bi, 0, "int")
  NumPut(w, bi, 4, "int"), NumPut(-h, bi, 8, "int")
  NumPut(1, bi, 12, "short"), NumPut(bpp, bi, 14, "short")
  ;-------------------------
  if hBM:=DllCall("CreateDIBSection", Ptr,mDC, Ptr,&bi
    , "int",0, PtrP,ppvBits, Ptr,0, "int",0, Ptr)
  {
    oBM:=DllCall("SelectObject", Ptr,mDC, Ptr,hBM, Ptr)
    DllCall("BitBlt", Ptr,mDC, "int",0, "int",0, "int",w, "int",h
      , Ptr,hDC, "int",x, "int",y, "uint",0x00CC0020|0x40000000)
    DllCall("RtlMoveMemory", Ptr,Scan0, Ptr,ppvBits, Ptr,Stride*h)
    DllCall("SelectObject", Ptr,mDC, Ptr,oBM)
    DllCall("DeleteObject", Ptr,hBM)
  }
  DllCall("DeleteDC", Ptr,mDC)
  DllCall("ReleaseDC", Ptr,win, Ptr,hDC)
}

MCode(ByRef code, hex)
{
  ListLines, Off
  bch:=A_BatchLines
  SetBatchLines, -1
  VarSetCapacity(code, StrLen(hex)//2)
  Loop, % StrLen(hex)//2
    NumPut("0x" . SubStr(hex,2*A_Index-1,2), code, A_Index-1, "char")
  Ptr:=A_PtrSize ? "UPtr" : "UInt"
  DllCall("VirtualProtect", Ptr,&code, Ptr
    ,VarSetCapacity(code), "uint",0x40, Ptr . "*",0)
  SetBatchLines, %bch%
  ListLines, On
}

base64tobit(s)
{
  ListLines, Off
  Chars:="0123456789+/ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    . "abcdefghijklmnopqrstuvwxyz"
  SetFormat, IntegerFast, d
  StringCaseSense, On
  Loop, Parse, Chars
  {
    i:=A_Index-1, v:=(i>>5&1) . (i>>4&1)
      . (i>>3&1) . (i>>2&1) . (i>>1&1) . (i&1)
    s:=StrReplace(s,A_LoopField,v)
  }
  StringCaseSense, Off
  s:=SubStr(s,1,InStr(s,"1",0,0)-1)
  s:=RegExReplace(s,"[^01]+")
  ListLines, On
  return, s
}

bit2base64(s)
{
  ListLines, Off
  s:=RegExReplace(s,"[^01]+")
  s.=SubStr("100000",1,6-Mod(StrLen(s),6))
  s:=RegExReplace(s,".{6}","|$0")
  Chars:="0123456789+/ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    . "abcdefghijklmnopqrstuvwxyz"
  SetFormat, IntegerFast, d
  Loop, Parse, Chars
  {
    i:=A_Index-1, v:="|" . (i>>5&1) . (i>>4&1)
      . (i>>3&1) . (i>>2&1) . (i>>1&1) . (i&1)
    s:=StrReplace(s,v,A_LoopField)
  }
  ListLines, On
  return, s
}

ASCII(s)
{
  if RegExMatch(s,"(\d+)\.([\w+/]{3,})",r)
  {
    s:=RegExReplace(base64tobit(r2),".{" r1 "}","$0`n")
    s:=StrReplace(StrReplace(s,"0","_"),"1","0")
  }
  else s=
  return, s
}

; You can put the text library at the beginning of the script,
; and Use Pic(Text,1) to add the text library to Pic()'s Lib,
; Use Pic("comment1|comment2|...") to get text images from Lib

Pic(comments, add_to_Lib=0)
{
  static Lib:=[]
  if (add_to_Lib)
  {
    re:="<([^>]*)>[^$]+\$\d+\.[\w+/]{3,}"
    Loop, Parse, comments, |
      if RegExMatch(A_LoopField,re,r)
        Lib[Trim(r1)]:=r
    Lib[""]:=""
  }
  else
  {
    text:=""
    Loop, Parse, comments, |
      text.="|" . Lib[Trim(A_LoopField)]
    return, text
  }
}

PicN(number)
{
  return, Pic(Trim(RegExReplace(number,".","$0|"),"|"))
}

FindTextOCR(nX, nY, nW, nH, err1, err0, Text, Interval=5)
{
  OCR:="", Right_X:=nX+nW
  While (ok:=FindText(nX, nY, nW, nH, err1, err0, Text))
  {
    ; For multi text search, This is the number of text images found
    Loop, % ok.MaxIndex()
    {
      ; X is the X coordinates of the upper left corner
      ; and W is the width of the image have been found
      i:=A_Index, x:=ok[i].1, y:=ok[i].2
        , w:=ok[i].3, h:=ok[i].4, comment:=ok[i].5
      ; We need the leftmost X coordinates
      if (A_Index=1 or x<Left_X)
        Left_X:=x, Left_W:=w, Left_OCR:=comment
    }
    ; If the interval exceeds the set value, add "*" to the result
    OCR.=(A_Index>1 and Left_X-Last_X>Interval ? "*":"") . Left_OCR
    ; Update nX and nW for next search
    x:=Left_X+Left_W, nW:=(Right_X-x)//2, nX:=x+nW, Last_X:=x
  }
  Return, OCR
}


/***** C source code of machine code *****

int __attribute__((__stdcall__)) PicFind(
  int mode, int c, int n, unsigned char * Bmp
  , int Stride, int sx, int sy, int sw, int sh
  , char * text, int * s1, int * s0
  , int err1, int err0, int w1, int h1, int * allpos)
{
  int o, i, j, k, x, y, w, h, ok=0;
  int r, g, b, rr, gg, bb, e1, e0, len1, len0, max;
  w=sw-w1+1; h=sh-h1+1; k=sy*Stride+sx*4;
  // Generate Lookup Table
  o=len1=len0=0;
  for (y=0; y<h1; y++)
  {
    for (x=0; x<w1; x++)
    {
      j=y*Stride+x*4;
      if (text[o++]=='1')
        s1[len1++]=j;
      else
        s0[len0++]=j;
    }
  }
  max=len1>len0 ? len1 : len0;
  // Color Mode
  if (mode==0)
  {
    for (y=0; y<h; y++)
    {
      for (x=0; x<w; x++)
      {
        o=y*Stride+x*4+k; e1=err1; e0=err0;
        j=o+c; rr=Bmp[2+j]; gg=Bmp[1+j]; bb=Bmp[j];
        for (i=0; i<max; i++)
        {
          if (i<len1)
          {
            j=o+s1[i]; r=Bmp[2+j]-rr; g=Bmp[1+j]-gg; b=Bmp[j]-bb;
            if (r<0) r=-r; if (g<0) g=-g; if (b<0) b=-b;
            if (r+g+b>n && (--e1)<0) goto NoMatch1;
          }
          if (i<len0)
          {
            j=o+s0[i]; r=Bmp[2+j]-rr; g=Bmp[1+j]-gg; b=Bmp[j]-bb;
            if (r<0) r=-r; if (g<0) g=-g; if (b<0) b=-b;
            if (r+g+b<=n && (--e0)<0) goto NoMatch1;
          }
        }
        allpos[ok++]=(sy+y)<<16|(sx+x);
        if (ok>=1024) goto Return1;
        NoMatch1:
        continue;
      }
    }
    goto Return1;
  }
  // Gray Threshold Mode
  c=(c+1)*1000;
  for (y=0; y<sh; y++)
  {
    for (x=0; x<sw; x++)
    {
      o=y*Stride+x*4+k;
      Bmp[3+o]=Bmp[2+o]*299+Bmp[1+o]*587+Bmp[o]*114<c ? 1:0;
    }
  }
  k=k+3;
  for (y=0; y<h; y++)
  {
    for (x=0; x<w; x++)
    {
      o=y*Stride+x*4+k; e1=err1; e0=err0;
      for (i=0; i<max; i++)
      {
        if (i<len1 && Bmp[o+s1[i]]!=1 && (--e1)<0) goto NoMatch2;
        if (i<len0 && Bmp[o+s0[i]]!=0 && (--e0)<0) goto NoMatch2;
      }
      allpos[ok++]=(sy+y)<<16|(sx+x);
      if (ok>=1024) goto Return1;
      NoMatch2:
      continue;
    }
  }
  Return1:
  return ok;
}

*/


; Note: This function is used for combination lookup,
; for example, a 0-9 text library has been set up,
; then any ID number can be found.
; Use Pic(Text,1) and PicN(number) when using.
; Only grayscale threshold mode is currently supported.

FindText2(x,y,w,h,err1,err0,text)
{
  xywh2xywh(x-w,y-h,2*w+1,2*h+1,x,y,w,h)
  if (w<1 or h<1)
    return, 0
  bch:=A_BatchLines
  SetBatchLines, -1
  ;--------------------------------------
  GetBitsFromScreen(x,y,w,h,Scan0,Stride,bits)
  ;--------------------------------------
  sx:=0, sy:=0, sw:=w, sh:=h
  arr:=[], info:=[], allv:="", allw:=0, Comment:=""
  if (err1=0 and err0=0)
    err1:=err0:=0.05
  Loop, Parse, text, |
  {
    v:=A_LoopField
    IfNotInString, v, $, Continue
    ; You Can Add Comment Text within The <>
    if RegExMatch(v,"<([^>]*)>",r)
      v:=StrReplace(v,r), Comment.=Trim(r1)
    ; You can Add two fault-tolerant in the [], separated by commas
    if RegExMatch(v,"\[([^\]]*)]",r)
    {
      v:=StrReplace(v,r), r1.=","
      StringSplit, r, r1, `,
      e1:=r1, e0:=r2
    }
    else e1:=err1, e0:=err0
    StringSplit, r, v, $
    color:=r1, v:=r2
    if !InStr(color,"*")
      Continue
    StringSplit, r, v, .
    w1:=r1, v:=base64tobit(r2), h1:=StrLen(v)//w1
    if (r0<2 or h1<1 or w1>sw or h1>sh or StrLen(v)!=w1*h1)
      Continue
    if InStr(color,"-")
    {
      r:=e1, e1:=e0, e0:=r, v:=StrReplace(v,"1","_")
      v:=StrReplace(StrReplace(v,"0","1"),"_","0")
      color:=StrReplace(color,"-")
    }
    color:=StrReplace(color,"*"), allw+=w1
    StrReplace(v,"1","",len1), len0:=StrLen(v)-len1
    e1:=Round(len1*e1), e0:=Round(len0*e0)
    info.Push(StrLen(allv),w1,h1,len1,len0,e1,e0), allv.=v
  }
  if (allv="")
  {
    SetBatchLines, %bch%
    return, 0
  }
  num:=info.MaxIndex(), VarSetCapacity(in,num*4,0), i:=-4
  Loop, % num
    NumPut(info[A_Index], in, i+=4, "int")
  VarSetCapacity(ss, sw*sh, 0), k:=StrLen(allv)*4
  VarSetCapacity(s1, k, 0), VarSetCapacity(s0, k, 0)
  VarSetCapacity(allpos, 1024*4, 0)
  offsetX:=5, offsetY:=5
  if (ok:=PicFind2(color,offsetX,offsetY,Scan0,Stride
    ,sx,sy,sw,sh,ss,allv,s1,s0,in,num,allpos))
  {
    Loop, % ok
      pos:=NumGet(allpos, 4*(A_Index-1), "uint")
      , rx:=(pos&0xFFFF)+x, ry:=(pos>>16)+y
      , arr.Push( [rx,ry,allw,h1,Comment] )
  }
  SetBatchLines, %bch%
  return, arr.MaxIndex() ? arr:0
}

PicFind2(color, offsetX, offsetY
  , Scan0, Stride, sx, sy, sw, sh
  , ByRef ss, ByRef text, ByRef s1, ByRef s0
  , ByRef in, num, ByRef allpos)
{
  static MyFunc
  if !MyFunc
  {
    x32:="5589E55383C480C745DC00000000C745EC00000000E9DA0"
    . "000008B45EC8D1485000000008B453C01D08B008945CC8B45C"
    . "C8945D88B45D88945F88B45EC83C0018D1485000000008B453"
    . "C01D08B008945B88B45EC83C0028D1485000000008B453C01D"
    . "08B008945B4C745F000000000EB77C745F400000000EB628B4"
    . "5F00FAF452489C28B45F401D08945E88B45F88D50018955F88"
    . "9C28B453001D00FB6003C31751C8B45D88D50018955D88D148"
    . "5000000008B453401C28B45E88902EB1A8B45CC8D50018955C"
    . "C8D1485000000008B453801C28B45E889028345F4018B45F43"
    . "B45B87C968345F0018B45F03B45B47C818345EC078B45EC3B4"
    . "5400F8C1AFFFFFF8B450883C00169C0E80300008945088B452"
    . "00FAF45188B551CC1E20201D08945F88B5524B80000000029D"
    . "0C1E00289C28B451801D08945E8C745EC00000000C745F0000"
    . "00000EB7FC745F400000000EB648B55EC8B452C01D08B55F88"
    . "3C20289D18B551401CA0FB6120FB6D269CA2B0100008B55F88"
    . "3C20189D38B551401DA0FB6120FB6D269D24B0200008D1C118"
    . "B4DF88B551401CA0FB6120FB6D26BD27201DA3B55080F9CC28"
    . "8108345F4018345F8048345EC018B45F43B45247C948345F00"
    . "18B45E80145F88B45F03B45280F8C75FFFFFF8B453C8B40048"
    . "945B88B453C8B40088945B48B453C8B400C8945B08B453C8B4"
    . "0108945AC8B453C8B40148945A88B453C8B40188945A48B452"
    . "42B45B88945A08B45282B45B489459C8B45B03945AC0F4D45A"
    . "C894598C745F000000000E91E030000C745F400000000E9020"
    . "300008B45F00FAF452489C28B45F401D08945F88B45A88945E"
    . "48B45A48945E0C745E800000000EB788B45E83B45B07D328B4"
    . "5E88D1485000000008B453401D08B108B45F801D089C28B452"
    . "C01D00FB6003C01740E836DE401837DE4000F889A0200008B4"
    . "5E83B45AC7D328B45E88D1485000000008B453801D08B108B4"
    . "5F801D089C28B452C01D00FB60084C0740E836DE001837DE00"
    . "00F88630200008345E8018B45E83B45987C808B55F48B45B80"
    . "1D083E8018945D48B45F02B45108945D0837DD0007907C745D"
    . "000000000C745EC07000000E9DF0100008B45EC8D148500000"
    . "0008B453C01D08B008945CC8B45EC83C0018D1485000000008"
    . "B453C01D08B008945948B45EC83C0028D1485000000008B453"
    . "C01D08B008945908B45EC83C0038D1485000000008B453C01D"
    . "08B0089458C8B45EC83C0048D1485000000008B453C01D08B0"
    . "08945888B45EC83C0058D1485000000008B453C01D08B00894"
    . "5848B45EC83C0068D1485000000008B453C01D08B008945808"
    . "B45242B45948945C08B55D48B450C01D08945E88B45E83B45C"
    . "07D068B45E88945C08B45282B45908945BC8B55F08B451001D"
    . "08945E88B45E83B45BC7D068B45E88945BC8B45D48945C8E9D"
    . "20000008B45D08945C4E9B70000008B45C40FAF452489C28B4"
    . "5C801D08945F88B45848945E48B45808945E0C745E80000000"
    . "0EB378B55CC8B45E801D08D1485000000008B453401D08B108"
    . "B45F801D089C28B452C01D00FB6003C01740A836DE401837DE"
    . "40078568345E8018B45E83B458C7CC1C745E800000000EB378"
    . "B55CC8B45E801D08D1485000000008B453801D08B108B45F80"
    . "1D089C28B452C01D00FB60084C0740A836DE001837DE000781"
    . "18345E8018B45E83B45887CC1EB2690EB01908345C4018B45C"
    . "43B45BC0F8E3DFFFFFF8345C8018B45C83B45C00F8E22FFFFF"
    . "FEB5B8B55C88B459401D083E8018945D48345EC078B45EC3B4"
    . "5400F8C15FEFFFF8B45DC8D50018955DC8D1485000000008B4"
    . "54401D08B4D208B55F001CA89D3C1E3108B4D1C8B55F401CA0"
    . "9DA8910817DDCFF0300007F28EB0490EB01908345F4018B45F"
    . "43B45A00F8EF2FCFFFF8345F0018B45F03B459C0F8ED6FCFFF"
    . "FEB01908B45DC83EC805B5DC24000"
    x64:="554889E54883C480894D10895518448945204C894D28C74"
    . "5E000000000C745F000000000E9FF0000008B45F04898488D1"
    . "48500000000488B45784801D08B008945D08B45D08945DC8B4"
    . "5DC8945FC8B45F048984883C001488D148500000000488B457"
    . "84801D08B008945BC8B45F048984883C002488D14850000000"
    . "0488B45784801D08B008945B8C745F400000000E984000000C"
    . "745F800000000EB6F8B45F40FAF454889C28B45F801D08945E"
    . "C8B45FC8D50018955FC4863D0488B45604801D00FB6003C317"
    . "5218B45DC8D50018955DC4898488D148500000000488B45684"
    . "801C28B45EC8902EB1F8B45D08D50018955D04898488D14850"
    . "0000000488B45704801C28B45EC89028345F8018B45F83B45B"
    . "C7C898345F4018B45F43B45B80F8C70FFFFFF8345F0078B45F"
    . "03B85800000000F8CF2FEFFFF8B451083C00169C0E80300008"
    . "945108B45400FAF45308B5538C1E20201D08945FC8B5548B80"
    . "000000029D0C1E00289C28B453001D08945ECC745F00000000"
    . "0C745F400000000E991000000C745F800000000EB768B45F04"
    . "863D0488B45584801D08B55FC83C2024863CA488B55284801C"
    . "A0FB6120FB6D269CA2B0100008B55FC83C2014C63C2488B552"
    . "84C01C20FB6120FB6D269D24B020000448D04118B55FC4863C"
    . "A488B55284801CA0FB6120FB6D26BD2724401C23B55100F9CC"
    . "288108345F8018345FC048345F0018B45F83B45487C828345F"
    . "4018B45EC0145FC8B45F43B45500F8C63FFFFFF488B45788B4"
    . "0048945BC488B45788B40088945B8488B45788B400C8945B44"
    . "88B45788B40108945B0488B45788B40148945AC488B45788B4"
    . "0188945A88B45482B45BC8945A48B45502B45B88945A08B45B"
    . "43945B00F4D45B089459CC745F400000000E97B030000C745F"
    . "800000000E95F0300008B45F40FAF454889C28B45F801D0894"
    . "5FC8B45AC8945E88B45A88945E4C745EC00000000E98800000"
    . "08B45EC3B45B47D3A8B45EC4898488D148500000000488B456"
    . "84801D08B108B45FC01D04863D0488B45584801D00FB6003C0"
    . "1740E836DE801837DE8000F88EC0200008B45EC3B45B07D3A8"
    . "B45EC4898488D148500000000488B45704801D08B108B45FC0"
    . "1D04863D0488B45584801D00FB60084C0740E836DE401837DE"
    . "4000F88AD0200008345EC018B45EC3B459C0F8C6CFFFFFF8B5"
    . "5F88B45BC01D083E8018945D88B45F42B45208945D4837DD40"
    . "07907C745D400000000C745F007000000E9180200008B45F04"
    . "898488D148500000000488B45784801D08B008945D08B45F04"
    . "8984883C001488D148500000000488B45784801D08B0089459"
    . "88B45F048984883C002488D148500000000488B45784801D08"
    . "B008945948B45F048984883C003488D148500000000488B457"
    . "84801D08B008945908B45F048984883C004488D14850000000"
    . "0488B45784801D08B0089458C8B45F048984883C005488D148"
    . "500000000488B45784801D08B008945888B45F048984883C00"
    . "6488D148500000000488B45784801D08B008945848B45482B4"
    . "5988945C48B55D88B451801D08945EC8B45EC3B45C47D068B4"
    . "5EC8945C48B45502B45948945C08B55F48B452001D08945EC8"
    . "B45EC3B45C07D068B45EC8945C08B45D88945CCE9E20000008"
    . "B45D48945C8E9C70000008B45C80FAF454889C28B45CC01D08"
    . "945FC8B45888945E88B45848945E4C745EC00000000EB3F8B5"
    . "5D08B45EC01D04898488D148500000000488B45684801D08B1"
    . "08B45FC01D04863D0488B45584801D00FB6003C01740A836DE"
    . "801837DE800785E8345EC018B45EC3B45907CB9C745EC00000"
    . "000EB3F8B55D08B45EC01D04898488D148500000000488B457"
    . "04801D08B108B45FC01D04863D0488B45584801D00FB60084C"
    . "0740A836DE401837DE40078118345EC018B45EC3B458C7CB9E"
    . "B2690EB01908345C8018B45C83B45C00F8E2DFFFFFF8345CC0"
    . "18B45CC3B45C40F8E12FFFFFFEB688B55CC8B459801D083E80"
    . "18945D88345F0078B45F03B85800000000F8CD9FDFFFF8B45E"
    . "08D50018955E04898488D148500000000488B8588000000480"
    . "1D08B4D408B55F401CAC1E2104189D08B4D388B55F801CA440"
    . "9C28910817DE0FF0300007F28EB0490EB01908345F8018B45F"
    . "83B45A40F8E95FCFFFF8345F4018B45F43B45A00F8E79FCFFF"
    . "FEB01908B45E04883EC805DC390909090909090"
    MCode(MyFunc, A_PtrSize=8 ? x64:x32)
  }
  return, DllCall(&MyFunc, "int",color, "int",offsetX
    , "int",offsetY, "ptr",Scan0, "int",Stride
    , "int",sx, "int",sy, "int",sw, "int",sh
    , "ptr",&ss, "AStr",text, "ptr",&s1, "ptr",&s0
    , "ptr",&in, "int",num, "ptr",&allpos)
}

/***** C source code of machine code *****

int __attribute__((__stdcall__)) PicFind2(
  int c, int offsetX, int offsetY
  , unsigned char * Bmp, int Stride
  , int sx, int sy, int sw, int sh
  , char * ss, char * text, int * s1, int * s0
  , int * in, int num, int * allpos )
{
  int o, x, y, i, j, max, e1, e0, ok=0;
  int o1, x1, y1, w1, h1, sx1, sy1, len1, len0, err1, err0;
  int o2, x2, y2, w2, h2, sx2, sy2, len21, len20, err21, err20;
  // Generate Lookup Table
  for (i=0; i<num; i+=7)
  {
    o=o1=o2=in[i]; w1=in[i+1]; h1=in[i+2];
    for (y=0; y<h1; y++)
    {
      for (x=0; x<w1; x++)
      {
        j=y*sw+x;
        if (text[o++]=='1')
          s1[o1++]=j;
        else
          s0[o2++]=j;
      }
    }
  }
  // Gray Threshold Mode
  c=(c+1)*1000; o=sy*Stride+sx*4; j=Stride-4*sw; i=0;
  for (y=0; y<sh; y++, o+=j)
  {
    for (x=0; x<sw; x++, o+=4, i++)
      ss[i]=Bmp[2+o]*299+Bmp[1+o]*587+Bmp[o]*114<c ? 1:0;
  }
  // Start Lookup
  w1=in[1]; h1=in[2]; len1=in[3]; len0=in[4]; err1=in[5]; err0=in[6];
  sx1=sw-w1; sy1=sh-h1; max=len1>len0 ? len1 : len0;
  for (y=0; y<=sy1; y++)
  {
    for (x=0; x<=sx1; x++)
    {
      o=y*sw+x; e1=err1; e0=err0;
      for (j=0; j<max; j++)
      {
        if (j<len1 && ss[o+s1[j]]!=1 && (--e1)<0) goto NoMatch1;
        if (j<len0 && ss[o+s0[j]]!=0 && (--e0)<0) goto NoMatch1;
      }
      x1=x+w1-1; y1=y-offsetY; if (y1<0) y1=0;
      for (i=7; i<num; i+=7)
      {
        o2=in[i]; w2=in[i+1]; h2=in[i+2];
        len21=in[i+3]; len20=in[i+4]; err21=in[i+5]; err20=in[i+6];
        sx2=sw-w2; j=x1+offsetX; if (j<sx2) sx2=j;
        sy2=sh-h2; j=y+offsetY; if (j<sy2) sy2=j;
        for (x2=x1; x2<=sx2; x2++)
        {
          for (y2=y1; y2<=sy2; y2++)
          {
            o=y2*sw+x2; e1=err21; e0=err20;
            for (j=0; j<len21; j++)
              if (ss[o+s1[o2+j]]!=1 && (--e1)<0) goto NoMatch2;
            for (j=0; j<len20; j++)
              if (ss[o+s0[o2+j]]!=0 && (--e0)<0) goto NoMatch2;
            goto MatchOK;
            NoMatch2:
            continue;
          }
        }
        goto NoMatch1;
        MatchOK:
        x1=x2+w2-1;
      }
      allpos[ok++]=(sy+y)<<16|(sx+x);
      if (ok>=1024) goto Return1;
      NoMatch1:
      continue;
    }
  }
  Return1:
  return ok;
}

*/


;================= The End =================

;
