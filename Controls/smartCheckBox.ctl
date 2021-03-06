VERSION 5.00
Begin VB.UserControl smartCheckBox 
   BackColor       =   &H80000005&
   ClientHeight    =   375
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   2520
   ClipControls    =   0   'False
   BeginProperty Font 
      Name            =   "Tahoma"
      Size            =   8.25
      Charset         =   0
      Weight          =   400
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   MousePointer    =   99  'Custom
   ScaleHeight     =   25
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   168
   ToolboxBitmap   =   "smartCheckBox.ctx":0000
End
Attribute VB_Name = "smartCheckBox"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon Checkbox control
'Copyright 2013-2015 by Tanner Helland
'Created: 28/January/13
'Last updated: 23/January/15
'Last update: overhaul font handling to match the lighter, cleaner approach of newer UCs
'
'In a surprise to precisely no one, PhotoDemon has some unique needs when it comes to user controls - needs that
' the intrinsic VB controls can't handle.  These range from the obnoxious (lack of an "autosize" property for
' anything but labels) to the critical (no Unicode support).
'
'As such, I've created many of my own UCs for the program.  All are owner-drawn, with the goal of maintaining
' visual fidelity across the program, while also enabling key features like Unicode support.
'
'A few notes on this checkbox replacement, specifically:
'
' 1) The control is no longer autosized based on the current font and caption.  If a caption exceeds the size of the
'     (manually set) width, the font size will be repeatedly reduced until the caption fits.
' 2) High DPI settings are handled automatically, so do not attempt to handle this manually.
' 3) A hand cursor is automatically applied, and clicks on both the button and label are registered properly.
' 4) Coloration is automatically handled by PD's internal theming engine.
' 5) When the control receives focus via keyboard, a special focus rect is drawn.  Focus via mouse is conveyed via text glow.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'This control really only needs one event raised - Click
Public Event Click()

'Flicker-free window painter
Private WithEvents cPainter As pdWindowPainter
Attribute cPainter.VB_VarHelpID = -1

'Retrieve the width and height of a string
Private Declare Function GetTextExtentPoint32 Lib "gdi32" Alias "GetTextExtentPoint32W" (ByVal hDC As Long, ByVal lpStrPointer As Long, ByVal cbString As Long, ByRef lpSize As POINTAPI) As Long

'Retrieve specific metrics on a font (in our case, crucial for aligning the radio button against the font baseline and ascender)
Private Declare Function GetTextMetrics Lib "gdi32" Alias "GetTextMetricsA" (ByVal hDC As Long, ByRef lpMetrics As TEXTMETRIC) As Long
Private Type TEXTMETRIC
    tmHeight As Long
    tmAscent As Long
    tmDescent As Long
    tmInternalLeading As Long
    tmExternalLeading As Long
    tmAveCharWidth As Long
    tmMaxCharWidth As Long
    tmWeight As Long
    tmOverhang As Long
    tmDigitizedAspectX As Long
    tmDigitizedAspectY As Long
    tmFirstChar As Byte
    tmLastChar As Byte
    tmDefaultChar As Byte
    tmBreakChar As Byte
    tmItalic As Byte
    tmUnderlined As Byte
    tmStruckOut As Byte
    tmPitchAndFamily As Byte
    tmCharSet As Byte
End Type

'API technique for drawing a focus rectangle; used only for designer mode (see the Paint method for details)
Private Declare Function DrawFocusRect Lib "user32" (ByVal hDC As Long, lpRect As RECT) As Long

'Previously, we used VB's internal label control to render the text caption.  This is now handled dynamically,
' via a pdFont object.
Private curFont As pdFont

'Rather than use an StdFont container (which requires VB to create redundant font objects), we track font properties manually,
' via dedicated properties.  At present, this control only exposes a Size font property.
Private m_FontSize As Single

'If the control's caption is too long, we must dynamically shrink the font size until an acceptable value is reached.
' This variable represents the *currently in-use font size*, not the font size property.
Private m_CurFontSize As Long

'Mouse input handler
Private WithEvents cMouseEvents As pdInputMouse
Attribute cMouseEvents.VB_VarHelpID = -1

'Current caption string (persistent within the IDE, but must be set at run-time for Unicode languages).  Note that m_CaptionEn
' is the ENGLISH CAPTION ONLY.  A translated caption will be stored in m_CaptionTranslated; the translated copy will be updated
' by any caption change, or by a call to updateAgainstCurrentTheme.
Private m_CaptionEn As String
Private m_CaptionTranslated As String

'If we cannot physically fit a translated caption into the user control's area (because we run out of allowable font sizes),
' this failure state will be set to TRUE.  When that happens, ellipses will be forcibly appended to the control caption.
Private m_FitFailure As Boolean

'Current control value
Private m_Value As CheckBoxConstants

'If we resize the UC in the designer, the back buffer obviously needs to be redrawn.  If we resize it as part of an internal
' AutoSize calculation, however, we will already be in the midst of resizing the back buffer - so we override the behavior
' of the UserControl_Resize event, using this variable.
Private m_InternalResizeState As Boolean

'Persistent back buffer, which we manage internally
Private m_BackBuffer As pdDIB

'If the mouse is currently INSIDE the control, this will be set to TRUE
Private m_MouseInsideUC As Boolean

'When the option button receives focus via keyboard (e.g. NOT by mouse events), we draw a focus rect to help orient the user.
Private m_FocusRectActive As Boolean

'Whenever the control is repainted, the clickable rect will be updated to reflect the relevant portion of the control's interior
Private clickableRect As RECT

'Additional helper for rendering themed and multiline tooltips
Private toolTipManager As pdToolTip

'The Enabled property is a bit unique; see http://msdn.microsoft.com/en-us/library/aa261357%28v=vs.60%29.aspx
Public Property Get Enabled() As Boolean
Attribute Enabled.VB_UserMemId = -514
    Enabled = UserControl.Enabled
End Property

Public Property Let Enabled(ByVal newValue As Boolean)
    
    UserControl.Enabled = newValue
    PropertyChanged "Enabled"
    
    'Redraw the control
    redrawBackBuffer
    
End Property

Public Property Get FontSize() As Single
    FontSize = m_FontSize
End Property

Public Property Let FontSize(ByVal newSize As Single)
    If newSize <> m_FontSize Then
        m_FontSize = newSize
        refreshFont
    End If
End Property

'When the font used for the caption changes in some way, it can be recreated (refreshed) using this function.  Note that font
' creation is expensive, so it's worthwhile to avoid this action as much as possible.
Private Sub refreshFont()
    
    Dim fontRefreshRequired As Boolean
    fontRefreshRequired = curFont.hasFontBeenCreated
    
    'Update each font parameter in turn.  If one (or more) requires a new font object, the font will be recreated as the final step.
    
    'Font face is always set automatically, to match the current program-wide font
    If (Len(g_InterfaceFont) <> 0) And (StrComp(curFont.getFontFace, g_InterfaceFont, vbBinaryCompare) <> 0) Then
        fontRefreshRequired = True
        curFont.setFontFace g_InterfaceFont
    End If
    
    'In the future, I may switch to GDI+ for font rendering, as it supports floating-point font sizes.  In the meantime, we check
    ' parity using an Int() conversion, as GDI only supports integer font sizes.
    If Int(m_FontSize) <> Int(curFont.getFontSize) Then
        fontRefreshRequired = True
        curFont.setFontSize m_FontSize
    End If
    
    'Request a new font, if one or more settings have changed
    If fontRefreshRequired Then curFont.createFontObject
    
    'Also, the back buffer needs to be rebuilt to reflect the new font metrics
    updateControlSize

End Sub

'The pdWindowPaint class raises this event when the control needs to be redrawn.  The passed coordinates contain the
' rect returned by GetUpdateRect (but with right/bottom measurements pre-converted to width/height).
Private Sub cPainter_PaintWindow(ByVal winLeft As Long, ByVal winTop As Long, ByVal winWidth As Long, ByVal winHeight As Long)

    'Flip the relevant chunk of the buffer to the screen
    BitBlt UserControl.hDC, winLeft, winTop, winWidth, winHeight, m_BackBuffer.getDIBDC, winLeft, winTop, vbSrcCopy
    
End Sub

'To improve responsiveness, MouseDown is used instead of Click
Private Sub cMouseEvents_MouseDownCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)

    If Me.Enabled And isMouseOverClickArea(x, y) Then
        If CBool(Me.Value) Then Me.Value = vbUnchecked Else Me.Value = vbChecked
    End If

End Sub

'When the mouse leaves the UC, we must repaint the caption (as it's no longer hovered)
Private Sub cMouseEvents_MouseLeave(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    
    If m_MouseInsideUC Then
        m_MouseInsideUC = False
        redrawBackBuffer
    End If
    
    'Reset the cursor
    cMouseEvents.setSystemCursor IDC_ARROW
    
End Sub

'When the mouse enters the clickable portion of the UC, we must repaint the caption (to reflect its hovered state)
Private Sub cMouseEvents_MouseMoveCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)

    'If the mouse is over the relevant portion of the user control, display the cursor as clickable
    If isMouseOverClickArea(x, y) Then
        
        cMouseEvents.setSystemCursor IDC_HAND
        
        'Repaint the control as necessary
        If Not m_MouseInsideUC Then
            m_MouseInsideUC = True
            redrawBackBuffer
        End If
    
    Else
    
        cMouseEvents.setSystemCursor IDC_ARROW
        
        'Repaint the control as necessary
        If m_MouseInsideUC Then
            m_MouseInsideUC = False
            redrawBackBuffer
        End If
        
    End If

End Sub

'See if the mouse is over the clickable portion of the control
Private Function isMouseOverClickArea(ByVal mouseX As Single, ByVal mouseY As Single) As Boolean
    
    If Math_Functions.isPointInRect(mouseX, mouseY, clickableRect) Then
        isMouseOverClickArea = True
    Else
        isMouseOverClickArea = False
    End If

End Function

Public Property Get hWnd() As Long
Attribute hWnd.VB_UserMemId = -515
    hWnd = UserControl.hWnd
End Property

'Container hWnd must be exposed for external tooltip handling
Public Property Get containerHwnd() As Long
    containerHwnd = UserControl.containerHwnd
End Property

Public Property Get Value() As CheckBoxConstants
Attribute Value.VB_UserMemId = 0
    Value = m_Value
End Property

Public Property Let Value(ByVal newValue As CheckBoxConstants)
    
    'Update our internal value tracker
    If m_Value <> newValue Then
    
        m_Value = newValue
        
        'Redraw the control; it's important to do this *before* raising the associated event, to maintain an impression of max responsiveness
        redrawBackBuffer
        
        'Notify the user of the change by raising the CLICK event
        RaiseEvent Click
        
    End If
    
    If Not g_IsProgramRunning Then PropertyChanged "Value"
    
End Property

'Caption is handled just like the common control label's caption property.  It is valid at design-time, and any translation,
' if present, will not be processed until run-time.
' IMPORTANT NOTE: only the ENGLISH caption is returned.  I don't have a reason for returning a translated caption (if any),
'                  but I can revisit in the future if that ever becomes relevant.
Public Property Get Caption() As String
Attribute Caption.VB_UserMemId = -518
    Caption = m_CaptionEn
End Property

Public Property Let Caption(ByVal newCaption As String)
    
    If StrComp(newCaption, m_CaptionEn, vbBinaryCompare) <> 0 Then
        
        m_CaptionEn = newCaption
        
        'During run-time, apply translations as necessary
        If g_IsProgramRunning Then
        
            'See if translations are necessary.
            Dim isTranslationActive As Boolean
                
            If Not (g_Language Is Nothing) Then
                If g_Language.translationActive Then
                    isTranslationActive = True
                Else
                    isTranslationActive = False
                End If
            Else
                isTranslationActive = False
            End If
            
            'Update the translated caption accordingly
            If isTranslationActive Then
                m_CaptionTranslated = g_Language.TranslateMessage(m_CaptionEn)
            Else
                m_CaptionTranslated = m_CaptionEn
            End If
        
        Else
            m_CaptionTranslated = m_CaptionEn
        End If
    
        PropertyChanged "Caption"
        
        'Captions are a bit strange; because the caption is auto-fitted to the control's width, changing the caption requires
        ' us to recalculate a number of layout metrics.
        updateControlSize
        
    End If
        
End Property

Private Sub UserControl_GotFocus()

    'If the mouse is *not* over the user control, assume focus was set via keyboard
    If Not m_MouseInsideUC Then
        m_FocusRectActive = True
        redrawBackBuffer
    End If

End Sub

Private Sub UserControl_Initialize()
    
    'Initialize the internal font object
    Set curFont = New pdFont
    curFont.setTextAlignment vbLeftJustify
    
    'When not in design mode, initialize a tracker for mouse events
    If g_IsProgramRunning Then
    
        Set cMouseEvents = New pdInputMouse
        cMouseEvents.addInputTracker Me.hWnd, True, True, , True
        cMouseEvents.setSystemCursor IDC_HAND
        
        'Also start a flicker-free window painter
        Set cPainter = New pdWindowPainter
        cPainter.startPainter Me.hWnd
        
        'Create a tooltip engine
        Set toolTipManager = New pdToolTip
        
    'In design mode, initialize a base theming class, so our paint function doesn't fail
    Else
        Set g_Themer = New pdVisualThemes
    End If
    
    m_MouseInsideUC = False
    m_FocusRectActive = False
        
    'Update the control size parameters at least once
    updateControlSize
                
End Sub

'Set default properties
Private Sub UserControl_InitProperties()
    
    Caption = "caption"
    m_FontSize = 10
    Value = vbChecked
    
End Sub

'Toggle the control's value upon space keypress
Private Sub UserControl_KeyPress(KeyAscii As Integer)

    If (KeyAscii = vbKeySpace) Then
        If CBool(Me.Value) Then Me.Value = vbUnchecked Else Me.Value = vbChecked
    End If

End Sub

Private Sub UserControl_LostFocus()

    'If a focus rect has been drawn, remove it now
    If (Not m_MouseInsideUC) And m_FocusRectActive Then
        m_FocusRectActive = False
        redrawBackBuffer
    End If

End Sub

'At run-time, painting is handled by PD's pdWindowPainter class.  In the IDE, however, we must rely on VB's internal paint event.
Private Sub UserControl_Paint()
    
    'Provide minimal painting within the designer
    If Not g_IsProgramRunning Then redrawBackBuffer
    
End Sub

Private Sub UserControl_ReadProperties(PropBag As PropertyBag)

    With PropBag
        Caption = .ReadProperty("Caption", "")
        FontSize = .ReadProperty("FontSize", 10)
        Value = .ReadProperty("Value", vbChecked)
    End With

End Sub

'The control dynamically resizes its font to make sure the full caption fits within the control area.
Private Sub UserControl_Resize()
    If (Not m_InternalResizeState) Then updateControlSize
End Sub

'Whenever the size of the control changes, we must recalculate some internal rendering metrics.
Private Sub updateControlSize()
    
    'Remove our font object from the buffer DC, because we are about to recreate it
    curFont.releaseFromDC
    
    'By adjusting this fontY parameter, we can control the auto-height of a created check box.  (This value is used
    ' as a padding constant, at present.)
    Dim fontY As Long
    fontY = 1
    
    'If the back buffer has not been created, create it now, so we can select the font object into it.
    If (m_BackBuffer Is Nothing) Then Set m_BackBuffer = New pdDIB
    
    'Manually create a (1, 1) buffer if one does not already exist.  (The buffer will be properly sized at a subsequent step.)
    If (UserControl.ScaleWidth = 0) Or (UserControl.ScaleHeight = 0) Or (m_BackBuffer.getDIBWidth = 0) Then
        m_BackBuffer.createBlank 1, 1, 24
    End If
    
    'Always start by setting the current font size to match the default font size property value.
    m_CurFontSize = m_FontSize
    If m_CurFontSize <> Int(curFont.getFontSize) Then
        curFont.setFontSize m_CurFontSize
        curFont.createFontObject
    End If
    curFont.attachToDC m_BackBuffer.getDIBDC
        
    'Auto-fitting the caption requires us to fit the entire (translated!) caption within the control's pre-set boundaries.
    Dim stringWidth As Long, stringHeight As Long
    Dim controlWidth As Long, controlHeight As Long
    controlWidth = UserControl.ScaleWidth
    controlHeight = UserControl.ScaleHeight
    
    'Start by measuring the font relative to the current control size.  This step is a little more complicated than usual,
    ' because we can't just measure the caption - we also have to calculate a matching size for the check box, and factor
    ' that (plus padding) into the width calculation.
    stringWidth = getCheckboxPlusCaptionWidth(m_CaptionTranslated)
            
    'If the caption + checkbox + padding does not fit within the control, test increasingly smaller fonts until a satisfying
    ' size has been reached.  If we reach font size 8 and still can't fit the caption, it will be forcibly truncated.
    Do While (stringWidth > controlWidth) And (m_CurFontSize >= 8)
        
        'Shrink the font size
        m_CurFontSize = m_CurFontSize - 1
        
        'Recreate the font
        curFont.releaseFromDC
        curFont.setFontSize m_CurFontSize
        curFont.createFontObject
        curFont.attachToDC m_BackBuffer.getDIBDC
        
        'Measure the new size
        stringWidth = getCheckboxPlusCaptionWidth(m_CaptionTranslated)
        
    Loop
    
    'If the font is at normal size, there is a small chance that the existing UC size will not be tall enough
    ' (vertically) to hold it.  This is due to rendering differences between Tahoma (on XP) and Segoe UI
    ' (on Vista+).  As such, we perform a failsafe check on the caption's height, and increase the control size
    ' as necessary.
    Dim txtSize As POINTAPI
    GetTextExtentPoint32 m_BackBuffer.getDIBDC, StrPtr(m_CaptionTranslated), Len(m_CaptionTranslated), txtSize
    stringHeight = txtSize.y
    
    'Our height calculation is pretty simple: the caption size, plus a one-pixel border (for displaying keyboard focus)
    ' and whatever fontY padding is specified at the top of this function.
    Dim newControlHeight As Long
    newControlHeight = (fontY * 4 + stringHeight + fixDPI(2)) * TwipsPerPixelYFix
    
    If controlHeight * TwipsPerPixelYFix <> newControlHeight Then
        m_InternalResizeState = True
        UserControl.Height = newControlHeight
        m_InternalResizeState = False
    End If
    
    'We are now ready to recreate the backbuffer to its relevant size.
    If (UserControl.ScaleWidth <> m_BackBuffer.getDIBWidth) Or (UserControl.ScaleHeight <> m_BackBuffer.getDIBHeight) Then
        curFont.releaseFromDC
        m_BackBuffer.createBlank UserControl.ScaleWidth, UserControl.ScaleHeight, 24
        curFont.attachToDC m_BackBuffer.getDIBDC
    End If
    
    'If the caption still does not fit within the available area (typically because we reached the minimum allowable font
    ' size, but the caption was *still* too long), set a module-level failure state to TRUE.  This notifies the renderer
    ' that ellipses must be forcibly appended to the caption.
    If stringWidth > UserControl.ScaleWidth Then
        m_FitFailure = True
    Else
        m_FitFailure = False
    End If
    
    'm_FontSize will now contain the final size of the control's font, and curFont has been updated accordingly.
    ' We may proceed with rendering the control.
    redrawBackBuffer
            
End Sub

Private Sub UserControl_WriteProperties(PropBag As PropertyBag)

    'Store all associated properties
    With PropBag
        .WriteProperty "Caption", Caption, "caption"
        .WriteProperty "Value", Value, vbChecked
        .WriteProperty "FontSize", m_FontSize, 10
    End With
    
End Sub

'External functions can call this to request a redraw.  This is helpful for live-updating theme settings, as in the Preferences dialog.
Public Sub updateAgainstCurrentTheme()
    
    'Update the font to reflect the themed font
    curFont.setFontFace g_InterfaceFont
    curFont.createFontObject
    
    'Calculate a new translation, as necessary
    If g_IsProgramRunning Then
    
        'See if translations are necessary.
        Dim isTranslationActive As Boolean
            
        If Not (g_Language Is Nothing) Then
            If g_Language.translationActive Then
                isTranslationActive = True
            Else
                isTranslationActive = False
            End If
        Else
            isTranslationActive = False
        End If
        
        'Update the translated caption accordingly
        If isTranslationActive Then
            m_CaptionTranslated = g_Language.TranslateMessage(m_CaptionEn)
        Else
            m_CaptionTranslated = m_CaptionEn
        End If
    
    Else
        m_CaptionTranslated = m_CaptionEn
    End If
    
    'Update the current font, as necessary.
    ' (Note that this will also trigger a redraw, so we do not need to manually request one here.)
    refreshFont
    
End Sub

'Use this function to completely redraw the back buffer from scratch.  Note that this is computationally expensive compared to just flipping the
' existing buffer to the screen, so only redraw the backbuffer if the control state has somehow changed.
Private Sub redrawBackBuffer()

    'Start by erasing the back buffer
    If g_IsProgramRunning Then
        GDI_Plus.GDIPlusFillDIBRect m_BackBuffer, 0, 0, m_BackBuffer.getDIBWidth, m_BackBuffer.getDIBHeight, g_Themer.getThemeColor(PDTC_BACKGROUND_DEFAULT), 255
    Else
        m_BackBuffer.createBlank m_BackBuffer.getDIBWidth, m_BackBuffer.getDIBHeight, 24, RGB(255, 255, 255)
        curFont.attachToDC m_BackBuffer.getDIBDC
    End If
    
    'Colors used throughout this paint function are determined primarily control enablement
    Dim chkBoxColorBorder As Long, chkBoxColorFill As Long
    If Me.Enabled Then
        
        If m_MouseInsideUC Then
            chkBoxColorBorder = g_Themer.getThemeColor(PDTC_ACCENT_SHADOW)
            chkBoxColorFill = g_Themer.getThemeColor(PDTC_ACCENT_DEFAULT)
        Else
            chkBoxColorBorder = g_Themer.getThemeColor(PDTC_GRAY_DEFAULT)
            chkBoxColorFill = g_Themer.getThemeColor(PDTC_ACCENT_SHADOW)
        End If
        
    Else
        chkBoxColorBorder = g_Themer.getThemeColor(PDTC_DISABLED)
        chkBoxColorFill = g_Themer.getThemeColor(PDTC_DISABLED)
    End If
    
    'Next, determine the precise size of our caption, including all internal metrics.  (We need those so we can properly
    ' align the check box with the baseline of the font and the caps (not ascender!) height.
    Dim captionWidth As Long, captionHeight As Long
    captionWidth = curFont.getWidthOfString(m_CaptionTranslated)
    captionHeight = curFont.getHeightOfString(m_CaptionTranslated)
    
    'Retrieve the descent of the current font.
    Dim fontDescent As Long, fontMetrics As TEXTMETRIC
    GetTextMetrics m_BackBuffer.getDIBDC, fontMetrics
    fontDescent = fontMetrics.tmDescent
    
    'From the precise font metrics, determine a check box offset X and Y, and a check box size.  Note that 1px is manually
    ' added as part of maintaining a 1px border around the user control as a whole.
    Dim offsetX As Long, offsetY As Long, chkBoxSize As Long
    offsetX = 1 + fixDPI(2)
    offsetY = fontMetrics.tmInternalLeading + 1
    chkBoxSize = captionHeight - fontDescent
    chkBoxSize = chkBoxSize - fontMetrics.tmInternalLeading
    chkBoxSize = chkBoxSize + 1
    
    'Because GDI+ is finicky with antialiasing on odd-numbered sizes, force the size to the nearest even number
    If chkBoxSize Mod 2 = 1 Then
        chkBoxSize = chkBoxSize + 1
        offsetY = offsetY - 1
    End If
    
    'Draw a border for the checkbox regardless of value state
    GDI_Plus.GDIPlusDrawRectOutlineToDC m_BackBuffer.getDIBDC, offsetX, offsetY, offsetX + chkBoxSize, offsetY + chkBoxSize, chkBoxColorBorder, 255, 1
    
    'If the check box button is checked, draw a checkmark inside the border
    If CBool(m_Value) Then
        GDI_Plus.GDIPlusDrawLineToDC m_BackBuffer.getDIBDC, offsetX + 2, offsetY + (chkBoxSize \ 2), offsetX + (chkBoxSize \ 2) - 1.5, offsetY + chkBoxSize - 2.5, chkBoxColorFill, 255, fixDPI(2), True, LineCapRound
        GDI_Plus.GDIPlusDrawLineToDC m_BackBuffer.getDIBDC, offsetX + (chkBoxSize \ 2) - 1, (offsetY + chkBoxSize) - 3, (offsetX + chkBoxSize) - 2, offsetY + 2, chkBoxColorFill, 255, fixDPI(2), True, LineCapRound
    End If
    
    'Set the text color according to the mouse position, e.g. highlight the text if the mouse is over it
    If Me.Enabled Then
    
        If m_MouseInsideUC Then
            curFont.setFontColor g_Themer.getThemeColor(PDTC_TEXT_HYPERLINK)
        Else
            curFont.setFontColor g_Themer.getThemeColor(PDTC_TEXT_DEFAULT)
        End If
        
    Else
        curFont.setFontColor g_Themer.getThemeColor(PDTC_DISABLED)
    End If
    
    'Failsafe check for designer mode
    If Not g_IsProgramRunning Then
        curFont.setFontColor RGB(0, 0, 0)
    End If
    
    'Render the text, appending ellipses as necessary
    Dim xFontOffset As Long
    xFontOffset = offsetX * 2 + chkBoxSize + fixDPI(6)
    
    If m_FitFailure Then
        curFont.fastRenderTextWithClipping xFontOffset, 1, m_BackBuffer.getDIBWidth - xFontOffset, m_BackBuffer.getDIBHeight, m_CaptionTranslated, True
    Else
        curFont.fastRenderTextWithClipping xFontOffset, 1, m_BackBuffer.getDIBWidth - xFontOffset, m_BackBuffer.getDIBHeight, m_CaptionTranslated, False
    End If
    
    'Update the clickable rect using the measurements from the final render
    With clickableRect
        .Left = 0
        .Top = 0
        .Right = xFontOffset + curFont.getWidthOfString(m_CaptionTranslated) + fixDPI(6)
        .Bottom = m_BackBuffer.getDIBHeight
    End With
    
    'If a focus rect is required (because focus was set via keyboard, not mouse), render it now.
    If m_FocusRectActive And m_MouseInsideUC Then m_FocusRectActive = False
    
    If m_FocusRectActive And Me.Enabled Then
        GDI_Plus.GDIPlusDrawRoundRect m_BackBuffer, 0, 0, clickableRect.Right, m_BackBuffer.getDIBHeight, 3, chkBoxColorFill, True, False
    End If
    
    'In the designer, draw a focus rect around the control; this is minimal feedback required for positioning
    If Not g_IsProgramRunning Then
        
        Dim tmpRect As RECT
        With tmpRect
            .Left = 0
            .Top = 0
            .Right = m_BackBuffer.getDIBWidth
            .Bottom = m_BackBuffer.getDIBHeight
        End With
        
        DrawFocusRect m_BackBuffer.getDIBDC, tmpRect

    End If
    
    'Paint the buffer to the screen
    If g_IsProgramRunning Then cPainter.requestRepaint Else BitBlt UserControl.hDC, 0, 0, m_BackBuffer.getDIBWidth, m_BackBuffer.getDIBHeight, m_BackBuffer.getDIBDC, 0, 0, vbSrcCopy

End Sub

'Estimate the size and offset of the checkbox and caption chunk of the control.  The function allows you to pass an arbitrary caption,
' which it uses to determine auto-shrinking of font size for lengthy translated captions.
Private Function getCheckboxPlusCaptionWidth(Optional ByVal relevantCaption As String = "") As Long

    If Len(relevantCaption) = 0 Then relevantCaption = m_CaptionTranslated

    'Start by retrieving caption width and height.  (Checkbox size is proportional to these values.)
    Dim captionWidth As Long, captionHeight As Long
    captionWidth = curFont.getWidthOfString(relevantCaption)
    captionHeight = curFont.getHeightOfString(relevantCaption)
    
    'Retrieve exact size metrics of the caption, as rendered in the current font
    Dim fontDescent As Long, fontMetrics As TEXTMETRIC
    GetTextMetrics m_BackBuffer.getDIBDC, fontMetrics
    fontDescent = fontMetrics.tmDescent
    
    'Using the font metrics, determine a check box offset and size.  Note that 1px is manually added as part of maintaining a
    ' 1px border around the user control as a whole (which is used for a focus rect).
    Dim offsetX As Long, offsetY As Long, chkBoxSize As Long
    offsetX = 1 + fixDPI(2)
    offsetY = fontMetrics.tmInternalLeading + 1
    chkBoxSize = captionHeight - fontDescent
    chkBoxSize = chkBoxSize - fontMetrics.tmInternalLeading
    chkBoxSize = chkBoxSize + 1
    
    'Because GDI+ is finicky with antialiasing on odd-numbered sizes, force the size to the nearest even number
    If chkBoxSize Mod 2 = 1 Then
        chkBoxSize = chkBoxSize + 1
        offsetY = offsetY - 1
    End If
    
    'Return the determined check box size, plus a 6px extender to separate it from the caption.
    getCheckboxPlusCaptionWidth = offsetX * 2 + chkBoxSize + fixDPI(6) + captionWidth

End Function

'Due to complex interactions between user controls and PD's translation engine, tooltips require this dedicated function.
' (IMPORTANT NOTE: the tooltip class will handle translations automatically.  Always pass the original English text!)
Public Sub assignTooltip(ByVal newTooltip As String, Optional ByVal newTooltipTitle As String, Optional ByVal newTooltipIcon As TT_ICON_TYPE = TTI_NONE)
    toolTipManager.setTooltip Me.hWnd, Me.containerHwnd, newTooltip, newTooltipTitle, newTooltipIcon
End Sub
