;///////////////////////////////////////////////////////////////////////////////////////////
; WebViewToo.ahk v1.0.1-geek-built
; Copyright (c) 2025 Ryan Dingman (known also as Panaku, The-CoDingman)
; https://github.com/The-CoDingman/WebViewToo
;
; MIT License
;
; Permission is hereby granted, free of charge, to any person obtaining a copy
; of this software and associated documentation files (the "Software"), to deal
; in the Software without restriction, including without limitation the rights
; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
; copies of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be included in all
; copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.
;///////////////////////////////////////////////////////////////////////////////////////////

#Requires AutoHotkey v2
/************************************************************************
 * @description Use Microsoft Edge WebView2 control in ahk.
 * @author thqby
 * @date 2025/01/09
 * @version 2.0.4
 * @webview2version 1.0.2903.40
 * @see {@link https://www.nuget.org/packages/Microsoft.Web.WebView2/ nuget package}
 * @see {@link https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/ API Reference}
 ***********************************************************************/
class WebView2 {
	static create(hwnd := -3, callback?, createdEnvironment := 0, dataDir := '', edgeRuntime := '', options := 0, dllPath := 'WebView2Loader.dll') {
		p := createdEnvironment ? createdEnvironment.CreateCoreWebView2ControllerAsync(hwnd) :
			this.CreateControllerAsync(hwnd, options, dataDir, edgeRuntime, dllPath)
		if !IsSet(callback)
			return p.await()
		p.then(callback)
	}
	/**
	 * create Edge WebView2 control.
	 * @param {Integer} hwnd the hwnd of Gui or Control.
	 * @param {$DirPath} dataDir User data folder.
	 * @param {$DirPath} edgeRuntime The path of Edge Runtime or Edge(dev..) Bin.
	 * @param {WebView2.EnvironmentOptions} options The environment options of Edge.
	 * @param {$FilePath} dllPath The path of `WebView2Loader.dll`.
	 * @returns {Promise<WebView2.Controller>}
	 */
	static CreateControllerAsync(hwnd := -3, options := 0, dataDir := '', edgeRuntime := '', dllPath := 'WebView2Loader.dll') {
		return this.CreateEnvironmentAsync(options, dataDir, edgeRuntime, dllPath)
			.then(r => r.CreateCoreWebView2ControllerAsync(hwnd))
	}

	/**
	 * create Edge WebView2 Environment.
	 * @param {WebView2.EnvironmentOptions} options The environment options of Edge.
	 * @param {$DirPath} dataDir User data folder.
	 * @param {$DirPath} edgeRuntime The path of Edge Runtime or Edge(dev..) Bin.
	 * @param {$FilePath} dllPath The path of `WebView2Loader.dll`.
	 * @returns {Promise<WebView2.Environment>}
	 */
	static CreateEnvironmentAsync(options := 0, dataDir := '', edgeRuntime := '', dllPath := 'WebView2Loader.dll') {
		if !edgeRuntime {
			ver := '0.0.0.0'
			for root in [EnvGet('ProgramFiles(x86)'), A_AppData '\..\Local']
				loop files root '\Microsoft\EdgeWebView\Application\*', 'D'
					if RegExMatch(A_LoopFilePath, '\\([\d.]+)$', &m) && VerCompare(m[1], ver) > 0
						edgeRuntime := A_LoopFileFullPath, ver := m[1]
		}
		if options && !(options is this.EnvironmentOptions) {
			if !options.HasOwnProp('TargetCompatibleBrowserVersion')
				options.TargetCompatibleBrowserVersion := ver
			options := this.EnvironmentOptions(options)
		}
		hModule := MemoryModule.LoadLibrary(%'WebView2Loader' A_PtrSize*8%())
		fnCreate := MemoryModule.GetProcAddress(hModule, "CreateCoreWebView2EnvironmentWithOptions")
		DllCall(fnCreate, 'str', edgeRuntime,
			'str', dataDir || RegExReplace(A_AppData, 'Roaming$', 'Local\Microsoft\Edge\User Data'), 'ptr', options,
			'ptr', this.AsyncHandler(&p, this.Environment), 'hresult')
		return p
	}

	/**
	 * @param {$FilePath} filePath
	 * @param {'r'|'w'|'rw'} mode
	 * - `r`, read-only mode, fails if the file doesn't exist.
	 * - `w`, read-write mode, creates a new file, overwriting any existing file.
	 * - `rw`, read-write mode, creates a new file if the file doesn't exist.
	 * @returns {WebView2.Stream}
	 */
	static CreateFileStream(filePath, mode := 'r') {
		DllCall('shlwapi\SHCreateStreamOnFileEx', 'wstr', filePath, 'uint',
			InStr(mode, 'w') && (!InStr(mode, 'r') || !FileExist(filePath) ? 0x1002 : 2),
			'uint', 128, 'int', 0, 'ptr', 0, 'ptr*', s := this.Stream(), 'hresult')
		return s
	}

	/**
	 * @param {Integer | Buffer} ptr
	 * @param {Integer} size
	 * @returns {WebView2.Stream}
	 */
	static CreateMemStream(ptr := 0, size := 0) {
		(s := this.Stream()).Ptr := DllCall('shlwapi\SHCreateMemStream', 'ptr', ptr,
			'uint', size || ptr && ptr.Size, 'ptr')
		return s
	}

	/**
	 * @param {String} text
	 * @param {String} encoding
	 * @returns {WebView2.Stream}
	 */
	static CreateTextStream(text, encoding := 'utf-8') {
		if encoding = 'utf-16'
			return this.CreateMemStream(StrPtr(text), StrLen(text) << 1)
		StrPut(text, buf := Buffer(StrPut(text, encoding) - 1), encoding)
		return this.CreateMemStream(buf)
	}

	/**
	 * @param {VarRef<Promise>} p
	 * @returns {WebView2.Handler}
	 */
	static AsyncHandler(&p, wrapper := 0) {
		p := Promise(executor.Bind(&ret, wrapper))
		return ret
		static executor(&ret, type, resolve, reject) {
			(ret := WebView2.Handler(handler)).reject := reject
			ret.resolve := type ? r => resolve(type(r)) : resolve
		}
		static handler(this, err, result := '') {
			this := ObjFromPtrAddRef(NumGet(this, A_PtrSize, 'ptr'))
			if err && (!result || err !== 0x80070057)
				(this.reject)(OSError(err))
			else
				(this.resolve)(result)
		}
	}

	/**
	 * @param {(sender, args)=>void} invoke 
	 * @param cls Subclass of WebView2.Base
	 * @param ea WebView2.xxxxEnventArgs
	 * @returns {WebView2.Handler} 
	 */
	static TypedHandler(invoke, cls, ea := 0) {
		e := WebView2.Handler(handler)
		e.invoke := invoke, e.cls := cls, e.ea := ea || v => v
		return e
		static handler(this, sender, args) {
			this := ObjFromPtrAddRef(NumGet(this, A_PtrSize, 'ptr'))
			(this.invoke)((this.cls)(sender), (this.ea)(args))
		}
	}

	; Interfaces Base class
	class Base {
		static Prototype.Ptr := 0
		/**
		 * Some interfaces with inheritance have different addresses for their objects.
		 * Incorrect use of methods that do not exist in the interface will cause the program to crash.
		 * For example, the object addresses for `FrameInfo` and `FrameInfo2` are different.
		 * By specifying the default IID, the interface is automatically queried when these objects are returned.
		 */
		static DefaultIID {
			set {
				this.Prototype.DefineProp('Ptr', { set: QueryInterface })
				QueryInterface(this, ptr) {
					if !ptr
						return
					obj := ComObjQuery(ptr, Value)
					if ptr !== nptr := ComObjValue(obj)
						ObjRelease(ptr), ObjAddRef(ptr := nptr)
					this.DefineProp('Ptr', { value: ptr })
				}
			}
		}
		; Re-implement the add_ method and automatically convert the ahk function into a delegate in webview2.
		static __New() {
			pthis := ObjPtr(this)
			for k in (proto := this.Prototype).OwnProps() {
				if SubStr(k, 1, 4) !== 'add_'
					continue
				if ObjHasOwnProp(WebView2, ea := SubStr(k, 5) 'EventArgs') ||
					ObjHasOwnProp(WebView2, ea := StrReplace(ea, 'Frame'))
					ea := WebView2.%ea%
				else ea := 0
				proto.DefineProp(k, { call: add_handler.Bind(proto.%k%, pthis, ea) })
			}
			static add_handler(method, pcls, ea, this, handler) {
				if !IsInteger(handler) && !(handler is WebView2.Handler) {
					if !HasMethod(handler, , 2)
						throw TypeError('Handler function requires 2 parameters.')
					handler := WebView2.TypedHandler(handler, ObjFromPtrAddRef(pcls), ea)
				}
				return method(this, handler)
			}
		}
		__New(ptr := 0) => ptr && (ObjAddRef(ptr), this.Ptr := ptr)
		__Delete() => (ptr := this.ptr) && ObjRelease(ptr)
		__Call(Name, Params) {
			if HasMethod(this, Name 'Async')
				return this.%Name%Async(Params*).await()
			if HasMethod(this, 'add_' Name)
				return { ptr: this.ptr, __Delete: this.remove_%Name%.Bind(, this.add_%Name%(Params[1])) }
			throw MethodError('This value of type "' this.__Class '" has no method named "' Name '".', -1)
		}
		/**
		 * Convert the object to another interface.
		 * @param {Class} cls A subclass of WebView2.base
		 * @param {String} iid
		 */
		as(cls, iid?) {
			ptr := ComObjValue(obj := ComObjQuery(this, iid ?? cls.IID))
			if ptr == this.Ptr
				ObjSetBase(this, cls.Prototype)
			else if this is cls
				ObjRelease(this.Ptr), ObjAddRef(this.Ptr := ptr)
			else return cls(ptr)
			return this
		}
		/**
		 * By default, an object in webview2 can be encapsulated as multiple different ahk objects,
		 * with independent properties. By calling this method, you can get its unique object in ahk.
		 * @returns {this}
		 */
		unique() {
			static caches := Map()
			if ptr := caches.Get(this.Ptr, 0)
				return ObjFromPtrAddRef(ptr)
			if ptr := this.Ptr {
				caches[ptr] := ObjPtr(this)
				cache := { Ptr: ptr, __Delete: this => caches.Delete(this.Ptr) }
				this.DefineProp('unique', { call: (this) => (cache, this) })
			}
			return this
		}
	}
	class List extends WebView2.Base {
		;@lint-disable class-non-dynamic-member-check
		__Item[index] => this.GetValueAtIndex(index)
		__Enum(n) {
			if n = 1
				return (n := this.Count, i := 0, (&v) => i < n ? (v := this.GetValueAtIndex(i++), true) : false)
			return (n := this.Count, i := 0, (&k, &v, *) => i < n ? (v := this.GetValueAtIndex(k := i++), true) : false)
		}
	}

	;#region WebView2 Interfaces
	class AcceleratorKeyPressedEventArgs extends WebView2.Base {
		static IID := '{9f760f8a-fb79-42be-9990-7b56900fa9c7}'
		KeyEventKind => (ComCall(3, this, 'int*', &keyEventKind := 0), keyEventKind)	; COREWEBVIEW2_KEY_EVENT_KIND
		VirtualKey => (ComCall(4, this, 'uint*', &virtualKey := 0), virtualKey)
		KeyEventLParam => (ComCall(5, this, 'int*', &lParam := 0), lParam)
		PhysicalKeyStatus => (ComCall(6, this, 'ptr*', physicalKeyStatus := WebView2.PHYSICAL_KEY_STATUS()), physicalKeyStatus)	; COREWEBVIEW2_PHYSICAL_KEY_STATUS
		Handled {
			get => (ComCall(7, this, 'int*', &handled := 0), handled)
			set => ComCall(8, this, 'int', Value)
		}

		static IID_2 := '{03b2c8c8-7799-4e34-bd66-ed26aa85f2bf}'
		IsBrowserAcceleratorKeyEnabled {
			get => (ComCall(9, this, 'int*', &value := 0), value)
			set => ComCall(10, this, 'int', Value)
		}
	}
	class BasicAuthenticationRequestedEventArgs extends WebView2.Base {
		static IID := '{ef05516f-d897-4f9e-b672-d8e2307a3fb0}'
		Uri => (ComCall(3, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		Challenge => (ComCall(4, this, 'ptr*', &challenge := 0), CoTaskMem_String(challenge))
		Response => (ComCall(5, this, 'ptr*', response := WebView2.BasicAuthenticationResponse()), response)
		Cancel {
			get => (ComCall(6, this, 'int*', &cancel := 0), cancel)
			set => ComCall(7, this, 'int', Value)
		}
		GetDeferral() => (ComCall(8, this, 'ptr*', deferral := WebView2.Deferral()), deferral)
	}
	class BasicAuthenticationResponse extends WebView2.Base {
		UserName {
			get => (ComCall(3, this, 'ptr*', &userName := 0), CoTaskMem_String(userName))
			set => ComCall(4, this, 'wstr', Value)
		}
		Password {
			get => (ComCall(5, this, 'ptr*', &password := 0), CoTaskMem_String(password))
			set => ComCall(6, this, 'wstr', Value)
		}
	}
	class BrowserExtension extends WebView2.Base {
		static IID := '{7EF7FFA0-FAC5-462C-B189-3D9EDBE575DA}'
		Id => (ComCall(3, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		Name => (ComCall(4, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		/** @returns {Promise<void>} */
		RemoveAsync() => (ComCall(5, this, 'ptr', WebView2.AsyncHandler(&p)), p)
		IsEnabled => (ComCall(6, this, 'int*', &value := 0), value)
		/** @returns {Promise<void>} */
		EnableAsync(isEnabled) => (ComCall(7, this, 'int', isEnabled, 'ptr', WebView2.AsyncHandler(&p)), p)
	}
	class BrowserExtensionList extends WebView2.List {
		static IID := '{2EF3D2DC-BD5F-4F4D-90AF-FD67798F0C2F}'
		Count => (ComCall(3, this, 'uint*', &count := 0), count)
		GetValueAtIndex(index) => (ComCall(4, this, 'uint', index, 'ptr*', extension := WebView2.BrowserExtension()), extension)
	}
	class BrowserProcessExitedEventArgs extends WebView2.Base {
		static IID := '{1f00663f-af8c-4782-9cdd-dd01c52e34cb}'
		BrowserProcessExitKind => (ComCall(3, this, 'int*', &browserProcessExitKind := 0), browserProcessExitKind)	; COREWEBVIEW2_BROWSER_PROCESS_EXIT_KIND
		BrowserProcessId => (ComCall(4, this, 'uint*', &value := 0), value)
	}
	class Certificate extends WebView2.Base {
		static IID := '{C5FB2FCE-1CAC-4AEE-9C79-5ED0362EAAE0}'
		Subject => (ComCall(3, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		Issuer => (ComCall(4, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		ValidFrom => (ComCall(5, this, 'double*', &value := 0), value)
		ValidTo => (ComCall(6, this, 'double*', &value := 0), value)
		DerEncodedSerialNumber => (ComCall(7, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		DisplayName => (ComCall(8, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		ToPemEncoding() => (ComCall(9, this, 'ptr*', &pemEncodedData := 0), CoTaskMem_String(pemEncodedData))
		PemEncodedIssuerCertificateChain => (ComCall(10, this, 'ptr*', value := WebView2.StringCollection()), value)
	}
	class CompositionController extends WebView2.Base {
		static IID := '{3df9b733-b9ae-4a15-86b4-eb9ee9826469}'
		RootVisualTarget {
			get => (ComCall(3, this, 'ptr*', &target := 0), ComValue(0xd, target))
			set => ComCall(4, this, 'ptr', Value)
		}
		SendMouseInput(eventKind, virtualKeys, mouseData, point) => ComCall(5, this, 'int', eventKind, 'int', virtualKeys, 'uint', mouseData, 'int64', point)
		SendPointerInput(eventKind, pointerInfo) => ComCall(6, this, 'int', eventKind, 'ptr', pointerInfo)	; ICoreWebView2PointerInfo
		Cursor => (ComCall(7, this, 'ptr*', &cursor := 0), cursor)
		SystemCursorId => (ComCall(8, this, 'uint*', &systemCursorId := 0), systemCursorId)
		/** @param {(sender: WebView2.CompositionController, args: IUnknown) => void} eventHandler */
		add_CursorChanged(eventHandler) => (ComCall(9, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2CursorChangedEventHandler
		remove_CursorChanged(token) => ComCall(10, this, 'int64', token)

		static IID_2 := '{0b6a3d24-49cb-4806-ba20-b5e0734a7b26}'
		AutomationProvider => (ComCall(11, this, 'ptr*', &provider := 0), ComValue(0xd, provider))

		static IID_3 := '{9570570e-4d76-4361-9ee1-f04d0dbdfb1e}'
		DragEnter(dataObject, keyState, point, peffect) => ComCall(12, this, 'ptr', dataObject, 'uint', keyState, 'int64', point, 'ptr', peffect)
		DragLeave() => ComCall(13, this)
		DragOver(keyState, point, peffect) => ComCall(14, this, 'uint', keyState, 'int64', point, 'ptr', peffect)
		Drop(dataObject, keyState, point, peffect) => ComCall(15, this, 'ptr', dataObject, 'uint', keyState, 'int64', point, 'ptr', peffect)

		static IID_4 := '{7C367B9B-3D2B-450F-9E58-D61A20F486AA}'
		GetNonClientRegionAtPoint(point) => (ComCall(16, this, 'int64', point, 'int*', &value := 0), value)	; COREWEBVIEW2_NON_CLIENT_REGION_KIND
		QueryNonClientRegion(kind) => (ComCall(17, this, 'int', kind, 'ptr*', rects := WebView2.RegionRectCollectionView()), rects)
		/** @param {(sender: WebView2.CompositionController, args: WebView2.NonClientRegionChangedEventArgs) => void} eventHandler */
		add_NonClientRegionChanged(eventHandler) => (ComCall(18, this, 'ptr', eventHandler, 'int64*', &token := 0), token)
		remove_NonClientRegionChanged(token) => ComCall(19, this, 'int64', token)
	}
	class Controller extends WebView2.Base {
		static IID := '{4d00c0d1-9434-4eb6-8078-8697a560334f}'
		Fill() {
			if !this.ptr
				return
			DllCall('user32\GetClientRect', 'ptr', this.ParentWindow, 'ptr', RECT := Buffer(16))
			this.Bounds := RECT
			return this
		}
		IsVisible {
			get => (ComCall(3, this, 'int*', &isVisible := 0), isVisible)
			set => ComCall(4, this, 'int', Value)
		}
		Bounds {
			get => (ComCall(5, this, 'ptr', bounds := WebView2.RECT()), bounds)
			set => A_PtrSize = 8 ? ComCall(6, this, 'ptr', Value) : ComCall(6, this, 'int64', NumGet(Value, 'int64'), 'int64', NumGet(Value, 8, 'int64'))
		}
		ZoomFactor {
			get => (ComCall(7, this, 'double*', &zoomFactor := 0), zoomFactor)
			set => ComCall(8, this, 'double', Value)
		}
		/** @param {(sender: WebView2.Controller, args: IUnknown) => void} eventHandler */
		add_ZoomFactorChanged(eventHandler) => (ComCall(9, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2ZoomFactorChangedEventHandler
		remove_ZoomFactorChanged(token) => ComCall(10, this, 'int64', token)
		SetBoundsAndZoomFactor(bounds, zoomFactor) => (A_PtrSize = 8 ? ComCall(11, this, 'ptr', bounds, 'double', zoomFactor) : ComCall(11, this, 'int64', NumGet(bounds, 'int64'), 'int64', NumGet(bounds, 8, 'int64'), 'double', zoomFactor))
		MoveFocus(reason) => ComCall(12, this, 'int', reason)
		/** @param {(sender: WebView2.Controller, args: WebView2.MoveFocusRequestedEventArgs) => void} eventHandler */
		add_MoveFocusRequested(eventHandler) => (ComCall(13, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2MoveFocusRequestedEventHandler
		remove_MoveFocusRequested(token) => ComCall(14, this, 'int64', token)
		/** @param {(sender: WebView2.Controller, args: IUnknown) => void} eventHandler */
		add_GotFocus(eventHandler) => (ComCall(15, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2FocusChangedEventHandler
		remove_GotFocus(token) => ComCall(16, this, 'int64', token)
		/** @param {(sender: WebView2.Controller, args: IUnknown) => void} eventHandler */
		add_LostFocus(eventHandler) => (ComCall(17, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2FocusChangedEventHandler
		remove_LostFocus(token) => ComCall(18, this, 'int64', token)
		/** @param {(sender: WebView2.Controller, args: WebView2.AcceleratorKeyPressedEventArgs) => void} eventHandler */
		add_AcceleratorKeyPressed(eventHandler) => (ComCall(19, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2AcceleratorKeyPressedEventHandler
		remove_AcceleratorKeyPressed(token) => ComCall(20, this, 'int64', token)
		ParentWindow {
			get => (ComCall(21, this, 'ptr*', &parentWindow := 0), parentWindow)
			set => ComCall(22, this, 'ptr', Value)
		}
		NotifyParentWindowPositionChanged() => ComCall(23, this)
		Close() => ComCall(24, this)
		CoreWebView2 => (ComCall(25, this, 'ptr*', coreWebView2 := WebView2.Core()), coreWebView2)

		static IID_2 := '{c979903e-d4ca-4228-92eb-47ee3fa96eab}'
		DefaultBackgroundColor {
			get => (ComCall(26, this, 'uint*', &backgroundColor := 0), backgroundColor)
			set => ComCall(27, this, 'uint', Value)
		}

		static IID_3 := '{f9614724-5d2b-41dc-aef7-73d62b51543b}'
		RasterizationScale {
			get => (ComCall(28, this, 'double*', &scale := 0), scale)
			set => ComCall(29, this, 'double', Value)
		}
		ShouldDetectMonitorScaleChanges {
			get => (ComCall(30, this, 'int*', &value := 0), value)
			set => ComCall(31, this, 'int', Value)
		}
		/** @param {(sender: WebView2.Controller, args: IUnknown) => void} eventHandler */
		add_RasterizationScaleChanged(eventHandler) => (ComCall(32, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2RasterizationScaleChangedEventHandler
		remove_RasterizationScaleChanged(token) => ComCall(33, this, 'int64', token)
		BoundsMode {
			get => (ComCall(34, this, 'int*', &boundsMode := 0), boundsMode)	; COREWEBVIEW2_BOUNDS_MODE
			set => ComCall(35, this, 'int', Value)
		}

		static IID_4 := '{97d418d5-a426-4e49-a151-e1a10f327d9e}'
		AllowExternalDrop {
			get => (ComCall(36, this, 'int*', &value := 0), value)
			set => ComCall(37, this, 'int', Value)
		}
	}
	class ControllerOptions extends WebView2.Base {
		static IID := '{12aae616-8ccb-44ec-bcb3-eb1831881635}'
		ProfileName {
			get => (ComCall(3, this, 'ptr*', &value := 0), CoTaskMem_String(value))
			set => ComCall(4, this, 'wstr', Value)
		}
		IsInPrivateModeEnabled {
			get => (ComCall(5, this, 'int*', &value := 0), value)
			set => ComCall(6, this, 'int', Value)
		}

		static IID_2 := '{06c991d8-9e7e-11ed-a8fc-0242ac120002}'
		ScriptLocale {
			get => (ComCall(7, this, 'ptr*', &value := 0), CoTaskMem_String(value))
			set => ComCall(8, this, 'wstr', Value)
		}
	}
	class ContentLoadingEventArgs extends WebView2.Base {
		static IID := '{0c8a1275-9b6b-4901-87ad-70df25bafa6e}'
		IsErrorPage => (ComCall(3, this, 'int*', &isErrorPage := 0), isErrorPage)
		NavigationId => (ComCall(4, this, 'int64*', &navigationId := 0), navigationId)
	}
	class ContextMenuItem extends WebView2.Base {
		static IID := '{7aed49e3-a93f-497a-811c-749c6b6b6c65}'
		Name => (ComCall(3, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		Label => (ComCall(4, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		CommandId => (ComCall(5, this, 'int*', &value := 0), value)
		ShortcutKeyDescription => (ComCall(6, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		Icon => (ComCall(7, this, 'ptr*', value := WebView2.Stream()), value)
		Kind => (ComCall(8, this, 'int*', &value := 0), value)
		IsEnabled {
			set => ComCall(9, this, 'int', Value)
			get => (ComCall(10, this, 'int*', &value := 0), value)
		}
		IsChecked {
			set => ComCall(11, this, 'int', Value)
			get => (ComCall(12, this, 'int*', &value := 0), value)
		}
		Children => (ComCall(13, this, 'ptr*', value := WebView2.ContextMenuItemCollection()), value)
		/** @param {(sender: WebView2.ContextMenuItem, args: IUnknown) => void} eventHandler */
		add_CustomItemSelected(eventHandler) => (ComCall(14, this, 'ptr', eventHandler, 'int64*', &token := 0), token)
		remove_CustomItemSelected(token) => ComCall(15, this, 'int64', token)
	}
	class ContextMenuItemCollection extends WebView2.List {
		static IID := '{f562a2f5-c415-45cf-b909-d4b7c1e276d3}'
		Count => (ComCall(3, this, 'uint*', &value := 0), value)
		GetValueAtIndex(index) => (ComCall(4, this, 'uint', index, 'ptr*', value := WebView2.ContextMenuItem()), value)
		RemoveValueAtIndex(index) => ComCall(5, this, 'uint', index)
		InsertValueAtIndex(index, value) => ComCall(6, this, 'uint', index, 'ptr', value)
	}
	class ContextMenuRequestedEventArgs extends WebView2.Base {
		static IID := '{a1d309ee-c03f-11eb-8529-0242ac130003}'
		MenuItems => (ComCall(3, this, 'ptr*', value := WebView2.ContextMenuItemCollection()), value)
		ContextMenuTarget => (ComCall(4, this, 'ptr*', value := WebView2.ContextMenuTarget()), value)
		Location => (ComCall(5, this, 'int64*', &value := 0), value)
		SelectedCommandId {
			set => ComCall(6, this, 'int', Value)
			get => (ComCall(7, this, 'int*', &value := 0), value)
		}
		Handled {
			set => ComCall(8, this, 'int', Value)
			get => (ComCall(9, this, 'int*', &value := 0), value)
		}
		GetDeferral() => (ComCall(10, this, 'ptr*', deferral := WebView2.Deferral()), deferral)
	}
	class ContextMenuTarget extends WebView2.Base {
		static IID := '{b8611d99-eed6-4f3f-902c-a198502ad472}'
		Kind => (ComCall(3, this, 'int*', &value := 0), value)	; COREWEBVIEW2_CONTEXT_MENU_TARGET_KIND
		IsEditable => (ComCall(4, this, 'int*', &value := 0), value)
		IsRequestedForMainFrame => (ComCall(5, this, 'int*', &value := 0), value)
		PageUri => (ComCall(6, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		FrameUri => (ComCall(7, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		HasLinkUri => (ComCall(8, this, 'int*', &value := 0), value)
		LinkUri => (ComCall(9, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		HasLinkText => (ComCall(10, this, 'int*', &value := 0), value)
		LinkText => (ComCall(11, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		HasSourceUri => (ComCall(12, this, 'int*', &value := 0), value)
		SourceUri => (ComCall(13, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		HasSelection => (ComCall(14, this, 'int*', &value := 0), value)
		Selection => (ComCall(15, this, 'ptr*', &value := 0), CoTaskMem_String(value))
	}
	class Cookie extends WebView2.Base {
		static IID := '{AD26D6BE-1486-43E6-BF87-A2034006CA21}'
		Name => (ComCall(3, this, 'ptr*', &name := 0), CoTaskMem_String(name))
		Value {
			get => (ComCall(4, this, 'ptr*', &value := 0), CoTaskMem_String(value))
			set => ComCall(5, this, 'wstr', Value)
		}
		Domain => (ComCall(6, this, 'ptr*', &domain := 0), CoTaskMem_String(domain))
		Path => (ComCall(7, this, 'ptr*', &path := 0), CoTaskMem_String(path))
		Expires {
			get => (ComCall(8, this, 'double*', &expires := 0), expires)
			set => ComCall(9, this, 'double', Value)
		}
		IsHttpOnly {
			get => (ComCall(10, this, 'int*', &isHttpOnly := 0), isHttpOnly)
			set => ComCall(11, this, 'int', Value)
		}
		SameSite {
			get => (ComCall(12, this, 'int*', &sameSite := 0), sameSite)	; COREWEBVIEW2_COOKIE_SAME_SITE_KIND
			set => ComCall(13, this, 'int', Value)
		}
		IsSecure {
			get => (ComCall(14, this, 'int*', &isSecure := 0), isSecure)
			set => ComCall(15, this, 'int', Value)
		}
		IsSession => (ComCall(16, this, 'int*', &isSession := 0), isSession)
	}
	class CookieList extends WebView2.List {
		static IID := '{F7F6F714-5D2A-43C6-9503-346ECE02D186}'
		Count => (ComCall(3, this, 'uint*', &count := 0), count)
		GetValueAtIndex(index) => (ComCall(4, this, 'uint', index, 'ptr*', cookie := WebView2.Cookie()), cookie)
	}
	class CookieManager extends WebView2.Base {
		static IID := '{177CD9E7-B6F5-451A-94A0-5D7A3A4C4141}'
		CreateCookie(name, value, domain, path) => (ComCall(3, this, 'wstr', name, 'wstr', value, 'wstr', domain, 'wstr', path, 'ptr*', cookie := WebView2.Cookie()), cookie)
		CopyCookie(cookieParam) => (ComCall(4, this, 'ptr', cookieParam, 'ptr*', cookie := WebView2.Cookie()), cookie)	; ICoreWebView2Cookie
		/** @returns {Promise<WebView2.CookieList>} */
		GetCookiesAsync(uri) => (ComCall(5, this, 'wstr', uri, 'ptr', WebView2.AsyncHandler(&p, WebView2.CookieList)), p)
		AddOrUpdateCookie(cookie) => ComCall(6, this, 'ptr', cookie)	; ICoreWebView2Cookie
		DeleteCookie(cookie) => ComCall(7, this, 'ptr', cookie)	; ICoreWebView2Cookie
		DeleteCookies(name, uri) => ComCall(8, this, 'wstr', name, 'wstr', uri)
		DeleteCookiesWithDomainAndPath(name, domain, path) => ComCall(9, this, 'wstr', name, 'wstr', domain, 'wstr', path)
		DeleteAllCookies() => ComCall(10, this)
	}
	class Core extends WebView2.Base {
		static IID := '{76eceacb-0462-4d94-ac83-423a6793775e}'
		/**
		 * - Add global variable `ahk = chrome.webview.hostObjects`.
		 * - Add `call(method='call',...args)` method for `KnownRemoteProxy` objects.
		 * - Add `get(prop='__Item',...args)` method for `KnownRemoteProxy` objects.
		 * - Add `set(prop='__Item',...args,val)` method for `KnownRemoteProxy` objects.
		 * - Add `then` method for `KnownRemoteProxy` objects.
		 * #### Compared with the original invoking method
		 * ```javascript
		 * let asyncArr = await ahk.arrayObj, syncArr = ahk.sync.arrayObj
		 * // call obj's method
		 * await asyncArr.call('Push',1,2,3)	// new
		 * await asyncArr.Push(asyncArr,1,2,3)	// original
		 * // get obj's non-existent property
		 * syncArr.get('non_existent')	// new, undefined
		 * syncArr.non_existent		// original, Proxy(function)
		 * // get obj's property without params
		 * syncArr.get('Length')	// new
		 * syncArr.Length		// original
		 * // set obj's property without params
		 * syncArr.set('Length',2)	// new
		 * syncArr.Length = 2	// original
		 * // get obj's dynamic property with params
		 * syncArr.get(null,2)	// new
		 * syncArr.GetOwnPropDesc(syncArr.Base,'__Item').Get(syncArr,2)	// original
		 * // set obj's dynamic property with params
		 * syncArr.set(null,2,0)	// new
		 * syncArr.GetOwnPropDesc(syncArr.Base,'__Item').Set(syncArr,0,2)	// original
		 * // await ahk's promise
		 * let p = ahk.promiseObj
		 * await p	// new
		 * await new Promise((resolve,reject) => p.Then(p,resolve,reject))	// original
		 * ```
		 */
		InjectAhkComponent() {
			static _ := !Promise.Prototype.DefineProp('then', {
				call: (this, resolve, reject) => !this.onSettled(resolve, err => reject(IsObject(err) ? err.Message : err)) })
			script := '
			(
			(function () {
				const { objectSerializer: OS, remoteMessenger: RM, remoteRefTracker: RRT } = (window.ahk = chrome.webview.hostObjects)._options;
				if (Object.hasOwn(OS, 'createKnownRemoteProxy'))
					return;
				const ahk_fns = ['call', 'get', 'set'];
				const { _serializationOptionsPropertyName: SOPN, createKnownRemoteProxy: CKRP } = OS;
				ahk._options.forceLocalProperties.push(...ahk_fns);
				OS.createKnownRemoteProxy = function (objId, thenable, sync, debugId, basis, hostKeyNames) {
					const proxy = CKRP.call(OS, objId, thenable, sync, debugId, basis, hostKeyNames);
					if (!basis && objId) {
						for (const k of ahk_fns) proxy.setLocalProperty(k, invoke.bind(proxy, k === 'call' ? 'apply' : k))
						thenable || proxy.setLocalProperty('then', then.bind(proxy));
					}
					return proxy;
				};
				function then(onfulfilled, onrejected) {
					return new Promise(async (resolve, reject) => {
						let thenable = this._debugId.at(-1) !== '\x05then()';
						try { thenable && await invoke.call(this, 'apply', '\x05then', resolve, err => reject(new Error(err))); }
						catch { thenable = false; }
						thenable || (delete this.then, resolve(this));
					}).then(onfulfilled, onrejected);
				}
				function invoke(operation, methodName, ...parameters) {
					const debugId = this._debugId.concat(operation === 'apply' ? (methodName ??= '') + '()' : methodName ||= '__item');
					if (!Object.hasOwn(this, '_resultObjectId')) {
						const promise = RM.postRequestMessage(this._remoteObjectId, methodName, operation, parameters);
						const resolve = getResult.bind(null, false, promise._callId, operation, debugId);
						return promise.then(resolve, resolve);
					}
					const callId = RM._idGenerator.getNextId();
					return getResult(true, operation, callId, debugId, RM._postRemoteProxyMessage(this._resultObjectId, methodName, {
						kind: "request", options: { operation, typedArrayIndices: RM.GetTypedArrayParametersIndices(parameters) }, parameters,
					}, callId, true));
				}
				function getResult(sync, operation, callId, debugId, rawResult) {
					const { error, has_object, result } = rawResult.parameters;
					if (error !== undefined)
						throw new Error(OS.deserialize(sync, false, debugId, error));
					if (has_object && result.hasOwnProperty(SOPN)) {
						if (operation === 'get') {
							const options = result[SOPN];
							if (options.seq_no && options.cache_able && options.groupId === 'native') {
								RRT.addSequenceId(options.seq_no), RRT._releaseObjectsCallback(RRT._maxRemoteSequenceId, options.remoteObjectId);
								delete OS._paramTracker[callId];
								return undefined;
							}
						}
						result.callId = callId;
					}
					const val = OS.deserialize(false, has_object, debugId, result);
					delete OS._paramTracker[callId];
					return val;
				}
			})();
			)'
			this.ExecuteScriptAsync(script)
			return this.AddScriptToExecuteOnDocumentCreatedAsync(script)
		}
		Settings => (ComCall(3, this, 'ptr*', settings := WebView2.Settings()), settings)
		Source => (ComCall(4, this, 'ptr*', &uri := 0), CoTaskMem_String(uri))
		Navigate(uri) => ComCall(5, this, 'wstr', uri)
		NavigateToString(htmlContent) => ComCall(6, this, 'wstr', htmlContent)
		/** @param {(sender: WebView2.Core, args: WebView2.NavigationStartingEventArgs) => void} eventHandler */
		add_NavigationStarting(eventHandler) => (ComCall(7, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2NavigationStartingEventHandler
		remove_NavigationStarting(token) => ComCall(8, this, 'int64', token)
		/** @param {(sender: WebView2.Core, args: WebView2.ContentLoadingEventArgs) => void} eventHandler */
		add_ContentLoading(eventHandler) => (ComCall(9, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2ContentLoadingEventHandler
		remove_ContentLoading(token) => ComCall(10, this, 'int64', token)
		/** @param {(sender: WebView2.Core, args: WebView2.SourceChangedEventArgs) => void} eventHandler */
		add_SourceChanged(eventHandler) => (ComCall(11, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2SourceChangedEventHandler
		remove_SourceChanged(token) => ComCall(12, this, 'int64', token)
		/** @param {(sender: WebView2.Core, args: IUnknown) => void} eventHandler */
		add_HistoryChanged(eventHandler) => (ComCall(13, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2HistoryChangedEventHandler
		remove_HistoryChanged(token) => ComCall(14, this, 'int64', token)
		/** @param {(sender: WebView2.Core, args: WebView2.NavigationCompletedEventArgs) => void} eventHandler */
		add_NavigationCompleted(eventHandler) => (ComCall(15, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2NavigationCompletedEventHandler
		remove_NavigationCompleted(token) => ComCall(16, this, 'int64', token)
		/** @param {(sender: WebView2.Core, args: WebView2.NavigationStartingEventArgs) => void} eventHandler */
		add_FrameNavigationStarting(eventHandler) => (ComCall(17, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2NavigationStartingEventHandler
		remove_FrameNavigationStarting(token) => ComCall(18, this, 'int64', token)
		/** @param {(sender: WebView2.Core, args: WebView2.NavigationCompletedEventArgs) => void} eventHandler */
		add_FrameNavigationCompleted(eventHandler) => (ComCall(19, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2NavigationCompletedEventHandler
		remove_FrameNavigationCompleted(token) => ComCall(20, this, 'int64', token)
		/** @param {(sender: WebView2.Core, args: WebView2.ScriptDialogOpeningEventArgs) => void} eventHandler */
		add_ScriptDialogOpening(eventHandler) => (ComCall(21, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2ScriptDialogOpeningEventHandler
		remove_ScriptDialogOpening(token) => ComCall(22, this, 'int64', token)
		/** @param {(sender: WebView2.Core, args: WebView2.PermissionRequestedEventArgs) => void} eventHandler */
		add_PermissionRequested(eventHandler) => (ComCall(23, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2PermissionRequestedEventHandler
		remove_PermissionRequested(token) => ComCall(24, this, 'int64', token)
		/** @param {(sender: WebView2.Core, args: WebView2.ProcessFailedEventArgs) => void} eventHandler */
		add_ProcessFailed(eventHandler) => (ComCall(25, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2ProcessFailedEventHandler
		remove_ProcessFailed(token) => ComCall(26, this, 'int64', token)
		/** @returns {Promise<String>} */
		AddScriptToExecuteOnDocumentCreatedAsync(javaScript) => (ComCall(27, this, 'wstr', javaScript, 'ptr', WebView2.AsyncHandler(&p, StrGet)), p)
		RemoveScriptToExecuteOnDocumentCreated(id) => ComCall(28, this, 'wstr', id)
		/** @returns {Promise<String>} */
		ExecuteScriptAsync(javaScript) => (ComCall(29, this, 'wstr', javaScript, 'ptr', WebView2.AsyncHandler(&p, StrGet)), p)
		/** @returns {Promise<void>} */
		CapturePreviewAsync(imageFormat, imageStream) => (ComCall(30, this, 'int', imageFormat, 'ptr', imageStream, 'ptr', WebView2.AsyncHandler(&p)), p)
		Reload() => ComCall(31, this)
		PostWebMessageAsJson(webMessageAsJson) => ComCall(32, this, 'wstr', webMessageAsJson)
		PostWebMessageAsString(webMessageAsString) => ComCall(33, this, 'wstr', webMessageAsString)
		/** @param {(sender: WebView2.Core, args: WebView2.WebMessageReceivedEventArgs) => void} eventHandler */
		add_WebMessageReceived(eventHandler) => (ComCall(34, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2WebMessageReceivedEventHandler
		remove_WebMessageReceived(token) => ComCall(35, this, 'int64', token)
		/** @returns {Promise<String>} */
		CallDevToolsProtocolMethodAsync(methodName, parametersAsJson) => (ComCall(36, this, 'wstr', methodName, 'wstr', parametersAsJson, 'ptr', WebView2.AsyncHandler(&p, StrGet)), p)
		BrowserProcessId => (ComCall(37, this, 'uint*', &value := 0), value)
		CanGoBack => (ComCall(38, this, 'int*', &canGoBack := 0), canGoBack)
		CanGoForward => (ComCall(39, this, 'int*', &canGoForward := 0), canGoForward)
		GoBack() => ComCall(40, this)
		GoForward() => ComCall(41, this)
		GetDevToolsProtocolEventReceiver(eventName) => (ComCall(42, this, 'wstr', eventName, 'ptr*', receiver := WebView2.DevToolsProtocolEventReceiver()), receiver)
		Stop() => ComCall(43, this)
		/** @param {(sender: WebView2.Core, args: WebView2.NewWindowRequestedEventArgs) => void} eventHandler */
		add_NewWindowRequested(eventHandler) => (ComCall(44, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2NewWindowRequestedEventHandler
		remove_NewWindowRequested(token) => ComCall(45, this, 'int64', token)
		/** @param {(sender: WebView2.Core, args: IUnknown) => void} eventHandler */
		add_DocumentTitleChanged(eventHandler) => (ComCall(46, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2DocumentTitleChangedEventHandler
		remove_DocumentTitleChanged(token) => ComCall(47, this, 'int64', token)
		DocumentTitle => (ComCall(48, this, 'ptr*', &title := 0), CoTaskMem_String(title))
		AddHostObjectToScript(name, object) => ComCall(49, this, 'wstr', name, 'ptr', ComVar(object))
		RemoveHostObjectFromScript(name) => ComCall(50, this, 'wstr', name)
		OpenDevToolsWindow() => ComCall(51, this)
		/** @param {(sender: WebView2.Core, args: IUnknown) => void} eventHandler */
		add_ContainsFullScreenElementChanged(eventHandler) => (ComCall(52, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2ContainsFullScreenElementChangedEventHandler
		remove_ContainsFullScreenElementChanged(token) => ComCall(53, this, 'int64', token)
		ContainsFullScreenElement => (ComCall(54, this, 'int*', &containsFullScreenElement := 0), containsFullScreenElement)
		/** @param {(sender: WebView2.Core, args: WebView2.WebResourceRequestedEventArgs) => void} eventHandler */
		add_WebResourceRequested(eventHandler) => (ComCall(55, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2WebResourceRequestedEventHandler
		remove_WebResourceRequested(token) => ComCall(56, this, 'int64', token)
		AddWebResourceRequestedFilter(uri, resourceContext) => ComCall(57, this, 'wstr', uri, 'int', resourceContext)
		RemoveWebResourceRequestedFilter(uri, resourceContext) => ComCall(58, this, 'wstr', uri, 'int', resourceContext)
		/** @param {(sender: WebView2.Core, args: IUnknown) => void} eventHandler */
		add_WindowCloseRequested(eventHandler) => (ComCall(59, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2WindowCloseRequestedEventHandler
		remove_WindowCloseRequested(token) => ComCall(60, this, 'int64', token)

		static IID_2 := '{9E8F0CF8-E670-4B5E-B2BC-73E061E3184C}'
		/** @param {(sender: WebView2.Core, args: WebView2.WebResourceResponseReceivedEventArgs) => void} eventHandler */
		add_WebResourceResponseReceived(eventHandler) => (ComCall(61, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2WebResourceResponseReceivedEventHandler
		remove_WebResourceResponseReceived(token) => ComCall(62, this, 'int64', token)
		NavigateWithWebResourceRequest(request) => ComCall(63, this, 'ptr', request)	; ICoreWebView2WebResourceRequest
		/** @param {(sender: WebView2.Core, args: WebView2.DOMContentLoadedEventArgs) => void} eventHandler */
		add_DOMContentLoaded(eventHandler) => (ComCall(64, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2DOMContentLoadedEventHandler
		remove_DOMContentLoaded(token) => ComCall(65, this, 'int64', token)
		CookieManager => (ComCall(66, this, 'ptr*', cookieManager := WebView2.CookieManager()), cookieManager)
		Environment => (ComCall(67, this, 'ptr*', environment := WebView2.Environment()), environment)

		static IID_3 := '{A0D6DF20-3B92-416D-AA0C-437A9C727857}'
		/** @returns {Promise<Integer>} */
		TrySuspendAsync() => (ComCall(68, this, 'ptr', WebView2.AsyncHandler(&p)), p)
		Resume() => ComCall(69, this)
		IsSuspended => (ComCall(70, this, 'int*', &isSuspended := 0), isSuspended)
		SetVirtualHostNameToFolderMapping(hostName, folderPath, accessKind) => ComCall(71, this, 'wstr', hostName, 'wstr', folderPath, 'int', accessKind)
		ClearVirtualHostNameToFolderMapping(hostName) => ComCall(72, this, 'wstr', hostName)

		static IID_4 := '{20d02d59-6df2-42dc-bd06-f98a694b1302}'
		/** @param {(sender: WebView2.Core, args: WebView2.FrameCreatedEventArgs) => void} eventHandler */
		add_FrameCreated(eventHandler) => (ComCall(73, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2FrameCreatedEventHandler
		remove_FrameCreated(token) => ComCall(74, this, 'int64', token)
		/** @param {(sender: WebView2.Core, args: WebView2.DownloadStartingEventArgs) => void} eventHandler */
		add_DownloadStarting(eventHandler) => (ComCall(75, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2DownloadStartingEventHandler
		remove_DownloadStarting(token) => ComCall(76, this, 'int64', token)

		static IID_5 := '{bedb11b8-d63c-11eb-b8bc-0242ac130003}'
		/** @param {(sender: WebView2.Core, args: WebView2.ClientCertificateRequestedEventArgs) => void} eventHandler */
		add_ClientCertificateRequested(eventHandler) => (ComCall(77, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2ClientCertificateRequestedEventHandler
		remove_ClientCertificateRequested(token) => ComCall(78, this, 'int64', token)

		static IID_6 := '{499aadac-d92c-4589-8a75-111bfc167795}'
		OpenTaskManagerWindow() => ComCall(79, this)

		static IID_7 := '{79c24d83-09a3-45ae-9418-487f32a58740}'
		/** @returns {Promise<Integer>} */
		PrintToPdfAsync(resultFilePath, printSettings) => (ComCall(80, this, 'wstr', resultFilePath, 'ptr', printSettings, 'ptr', WebView2.AsyncHandler(&p)), p)

		static IID_8 := '{E9632730-6E1E-43AB-B7B8-7B2C9E62E094}'
		/** @param {(sender: WebView2.Core, args: IUnknown) => void} eventHandler */
		add_IsMutedChanged(eventHandler) => (ComCall(81, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2IsMutedChangedEventHandler
		remove_IsMutedChanged(token) => ComCall(82, this, 'int64', token)
		IsMuted {
			get => (ComCall(83, this, 'int*', &value := 0), value)
			set => ComCall(84, this, 'int', Value)
		}
		/** @param {(sender: WebView2.Core, args: IUnknown) => void} eventHandler */
		add_IsDocumentPlayingAudioChanged(eventHandler) => (ComCall(85, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2IsDocumentPlayingAudioChangedEventHandler
		remove_IsDocumentPlayingAudioChanged(token) => ComCall(86, this, 'int64', token)
		IsDocumentPlayingAudio => (ComCall(87, this, 'int*', &value := 0), value)

		static IID_9 := '{4d7b2eab-9fdc-468d-b998-a9260b5ed651}'
		/** @param {(sender: WebView2.Core, args: IUnknown) => void} eventHandler */
		add_IsDefaultDownloadDialogOpenChanged(eventHandler) => (ComCall(88, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2IsDefaultDownloadDialogOpenChangedEventHandler
		remove_IsDefaultDownloadDialogOpenChanged(token) => ComCall(89, this, 'int64', token)
		IsDefaultDownloadDialogOpen => (ComCall(90, this, 'int*', &value := 0), value)
		OpenDefaultDownloadDialog() => ComCall(91, this)
		CloseDefaultDownloadDialog() => ComCall(92, this)
		DefaultDownloadDialogCornerAlignment {
			get => (ComCall(93, this, 'int*', &value := 0), value)
			set => ComCall(94, this, 'int', Value)
		}
		DefaultDownloadDialogMargin {
			get => (ComCall(95, this, 'int64*', &value := 0), value)	; POINT
			set => ComCall(96, this, 'int64', Value)
		}

		static IID_10 := '{b1690564-6f5a-4983-8e48-31d1143fecdb}'
		/** @param {(sender: WebView2.Core, args: WebView2.BasicAuthenticationRequestedEventArgs) => void} eventHandler */
		add_BasicAuthenticationRequested(eventHandler) => (ComCall(97, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2BasicAuthenticationRequestedEventHandler
		remove_BasicAuthenticationRequested(token) => ComCall(98, this, 'int64', token)

		static IID_11 := '{0be78e56-c193-4051-b943-23b460c08bdb}'
		/** @returns {Promise<String>} */
		CallDevToolsProtocolMethodForSessionAsync(sessionId, methodName, parametersAsJson) => (ComCall(99, this, 'wstr', sessionId, 'wstr', methodName, 'wstr', parametersAsJson, 'ptr', WebView2.AsyncHandler(&p, StrGet)), p)
		/** @param {(sender: WebView2.Core, args: WebView2.ContextMenuRequestedEventArgs) => void} eventHandler */
		add_ContextMenuRequested(eventHandler) => (ComCall(100, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2ContextMenuRequestedEventHandler
		remove_ContextMenuRequested(token) => ComCall(101, this, 'int64', token)

		static IID_12 := '{35D69927-BCFA-4566-9349-6B3E0D154CAC}'
		/** @param {(sender: WebView2.Core, args: IUnknown) => void} eventHandler */
		add_StatusBarTextChanged(eventHandler) => (ComCall(102, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2StatusBarTextChangedEventHandler
		remove_StatusBarTextChanged(token) => ComCall(103, this, 'int64', token)
		StatusBarText => (ComCall(104, this, 'ptr*', &value := 0), CoTaskMem_String(value))

		static IID_13 := '{F75F09A8-667E-4983-88D6-C8773F315E84}'
		Profile => (ComCall(105, this, 'ptr*', value := WebView2.Profile()), value)

		static IID_14 := '{6DAA4F10-4A90-4753-8898-77C5DF534165}'
		/** @param {(sender: WebView2.Core, args: WebView2.ServerCertificateErrorDetectedEventArgs) => void} eventHandler */
		add_ServerCertificateErrorDetected(eventHandler) => (ComCall(106, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2ServerCertificateErrorDetectedEventHandler
		remove_ServerCertificateErrorDetected(token) => ComCall(107, this, 'int64', token)
		/** @returns {Promise<void>} */
		ClearServerCertificateErrorActionsAsync() => (ComCall(108, this, 'ptr', WebView2.AsyncHandler(&p)), p)

		static IID_15 := '{517B2D1D-7DAE-4A66-A4F4-10352FFB9518}'
		/** @param {(sender: WebView2.Core, args: IUnknown) => void} eventHandler */
		add_FaviconChanged(eventHandler) => (ComCall(109, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2FaviconChangedEventHandler
		remove_FaviconChanged(token) => ComCall(110, this, 'int64', token)
		FaviconUri => (ComCall(111, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		/** @returns {Promise<WebView2.Stream>} */
		GetFaviconAsync(format) => (ComCall(112, this, 'int', format, 'ptr', WebView2.AsyncHandler(&p, WebView2.Stream)), p)	; COREWEBVIEW2_FAVICON_IMAGE_FORMAT

		static IID_16 := '{0EB34DC9-9F91-41E1-8639-95CD5943906B}'
		/** @returns {Promise<WebView2.PRINT_STATUS>} */
		PrintAsync(printSettings) => (ComCall(113, this, 'ptr', printSettings, 'ptr', WebView2.AsyncHandler(&p)), p)
		ShowPrintUI(printDialogKind) => ComCall(114, this, 'int', printDialogKind)
		/** @returns {Promise<WebView2.Stream>} */
		PrintToPdfStreamAsync(printSettings) => (ComCall(115, this, 'ptr', printSettings, 'ptr', WebView2.AsyncHandler(&p, WebView2.Stream)), p)

		static IID_17 := '{702E75D4-FD44-434D-9D70-1A68A6B1192A}'
		PostSharedBufferToScript(sharedBuffer, access, additionalDataAsJson) => ComCall(116, this, 'ptr', sharedBuffer, 'int', access, 'wstr', additionalDataAsJson)

		static IID_18 := '{7A626017-28BE-49B2-B865-3BA2B3522D90}'
		/** @param {(sender: WebView2.Core, args: WebView2.LaunchingExternalUriSchemeEventArgs) => void} eventHandler */
		add_LaunchingExternalUriScheme(eventHandler) => (ComCall(117, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2LaunchingExternalUriSchemeEventHandler
		remove_LaunchingExternalUriScheme(token) => ComCall(118, this, 'int64', token)

		static IID_19 := '{6921F954-79B0-437F-A997-C85811897C68}'
		MemoryUsageTargetLevel {
			get => (ComCall(119, this, 'int*', &level := 0), level)
			set => ComCall(120, this, 'int', Value)
		}

		static IID_20 := '{b4bc1926-7305-11ee-b962-0242ac120002}'
		FrameId => (ComCall(121, this, 'uint*', &id := 0), id)

		static IID_21 := '{c4980dea-587b-43b9-8143-3ef3bf552d95}'
		/** @returns {Promise<WebView2.ExecuteScriptResult>} */
		ExecuteScriptWithResultAsync(javaScript) => (ComCall(122, this, 'wstr', javaScript, 'ptr', WebView2.AsyncHandler(&p, WebView2.ExecuteScriptResult)), p)

		static IID_22 := '{DB75DFC7-A857-4632-A398-6969DDE26C0A}'
		AddWebResourceRequestedFilterWithRequestSourceKinds(uri, resourceContext, requestSourceKinds) => ComCall(123, this, 'wstr', uri, 'int', resourceContext, 'int', requestSourceKinds)
		RemoveWebResourceRequestedFilterWithRequestSourceKinds(uri, resourceContext, requestSourceKinds) => ComCall(124, this, 'wstr', uri, 'int', resourceContext, 'int', requestSourceKinds)

		static IID_23 := '{508f0db5-90c4-5872-90a7-267a91377502}'
		/**
		 * Same as PostWebMessageAsJson, but also has support for posting DOM objects to page content.
		 * @param {String} webMessageAsJson
		 * @param {WebView2.ObjectCollectionView} additionalObjects
		 */
		PostWebMessageAsJsonWithAdditionalObjects(webMessageAsJson, additionalObjects) => ComCall(125, this, 'wstr', webMessageAsJson, 'ptr', additionalObjects)

		static IID_24 := '{39a7ad55-4287-5cc1-88a1-c6f458593824}'
		/** @param {(sender: WebView2.Core, args: WebView2.NotificationReceivedEventArgs) => void} eventHandler */
		add_NotificationReceived(eventHandler) => (ComCall(126, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2LaunchingExternalUriSchemeEventHandler
		remove_NotificationReceived(token) => ComCall(127, this, 'int64', token)

		static IID_25 := '{b5a86092-df50-5b4f-a17b-6c8f8b40b771}'
		/** @param {(sender: WebView2.Core, args: WebView2.SaveAsUIShowingEventArgs) => void} eventHandler */
		add_SaveAsUIShowing(eventHandler) => (ComCall(128, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2LaunchingExternalUriSchemeEventHandler
		remove_SaveAsUIShowing(token) => ComCall(129, this, 'int64', token)
		/** @returns {Promise<WebView2.SAVE_AS_UI_RESULT>} */
		ShowSaveAsUIAsync() => (ComCall(130, this, 'ptr', WebView2.AsyncHandler(&p)), p)

		static IID_26 := '{806268b8-f897-5685-88e5-c45fca0b1a48}'
		/** @param {(sender: WebView2.Core, args: WebView2.SaveFileSecurityCheckStartingEventArgs) => void} eventHandler */
		add_SaveFileSecurityCheckStarting(eventHandler) => (ComCall(131, this, 'ptr', eventHandler, 'int64*', &token := 0), token)
		remove_SaveFileSecurityCheckStarting(token) => ComCall(132, this, 'int64', token)

		static IID_27 := '{00fbe33b-8c07-517c-aa23-0ddd4b5f6fa0}'
		/** @param {(sender: WebView2.Core, args: WebView2.ScreenCaptureStartingEventArgs) => void} eventHandler */
		add_ScreenCaptureStarting(eventHandler) => (ComCall(133, this, 'ptr', eventHandler, 'int64*', &token := 0), token)
		remove_ScreenCaptureStarting(token) => ComCall(134, this, 'int64', token)
	}
	class ClientCertificate extends WebView2.Base {
		static IID := '{e7188076-bcc3-11eb-8529-0242ac130003}'
		Subject => (ComCall(3, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		Issuer => (ComCall(4, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		ValidFrom => (ComCall(5, this, 'double*', &value := 0), value)
		ValidTo => (ComCall(6, this, 'double*', &value := 0), value)
		DerEncodedSerialNumber => (ComCall(7, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		DisplayName => (ComCall(8, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		ToPemEncoding() => (ComCall(9, this, 'ptr*', &pemEncodedData := 0), CoTaskMem_String(pemEncodedData))
		PemEncodedIssuerCertificateChain => (ComCall(10, this, 'ptr*', value := WebView2.StringCollection()), value)
		Kind => (ComCall(11, this, 'int*', &value := 0), value)	; COREWEBVIEW2_CLIENT_CERTIFICATE_KIND
	}
	class CustomSchemeRegistration extends Buffer {
		static IID := '{d60ac92c-37a6-4b26-a39e-95cfe59047bb}'
		/**
		 * Represents the registration of a custom scheme with the CoreWebView2Environment.
		 * https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2customschemeregistration
		 * @param {String} SchemeName The name of the custom scheme to register.
		 * @param {Array} AllowedOrigins The array of origins that are allowed to use the scheme.
		 * @param TreatAsSecure Whether the sites with this scheme will be treated as a Secure Context like an HTTPS site.
		 * @param HasAuthorityComponent Set this property to true if the URIs with this custom scheme will have an authority component (a host for custom schemes).
		 */
		__New(SchemeName, AllowedOrigins, TreatAsSecure := false, HasAuthorityComponent := false) {
			super.__New(11 * A_PtrSize)
			p_this := ObjPtr(this), p_unk := this.Ptr + A_PtrSize
			p := NumPut('ptr', p_unk, this), fnptrs := []
			this.DefineProp('__Delete', { call: __Delete })
			for cb in [
				QueryInterface, AddRef, Release,
				get_SchemeName, get_TreatAsSecure, put_xxx,
				GetAllowedOrigins, SetAllowedOrigins,
				get_HasAuthorityComponent, put_xxx
			]
				p := NumPut('ptr', _ := CallbackCreate(cb), p), fnptrs.Push(_)
			QueryInterface(this, riid, ppvObject) {
				DllCall("ole32.dll\StringFromGUID2", "ptr", riid, "ptr", buf := Buffer(78), "int", 39)
				iid := StrGet(buf)
				if iid = '{d60ac92c-37a6-4b26-a39e-95cfe59047bb}' {
					ObjAddRef(p_this), NumPut('ptr', p_unk, ppvObject)
					return 0
				}
				NumPut('ptr', 0, ppvObject)
				return 0x80004002
			}
			AddRef(this) => ObjAddRef(p_this)
			Release(this) => ObjRelease(p_this)
			put_xxx(this, value) => 0
			get_SchemeName(this, pvalue) {
				p := DllCall('ole32\CoTaskMemAlloc', 'uptr', s := StrLen(SchemeName) * 2 + 2, 'ptr')
				DllCall('RtlMoveMemory', 'ptr', p, 'ptr', StrPtr(SchemeName), 'uptr', s)
				return (NumPut('ptr', p, pvalue), 0)
			}
			get_TreatAsSecure(this, pvalue) => (NumPut('int', TreatAsSecure, pvalue), 0)
			get_HasAuthorityComponent(this, pvalue) => (NumPut('int', HasAuthorityComponent, pvalue), 0)
			GetAllowedOrigins(this, pallowedOriginsCount, pallowedOrigins) {
				local l, p, p, ps
				NumPut('uint', l := AllowedOrigins.Length, pallowedOriginsCount)
				if l {
					p := p := DllCall('ole32\CoTaskMemAlloc', 'uptr', l * A_PtrSize, 'ptr')
					for origin in AllowedOrigins {
						ps := DllCall('ole32\CoTaskMemAlloc', 'uptr', s := StrLen(origin) * 2 + 2, 'ptr')
						DllCall('RtlMoveMemory', 'ptr', ps, 'ptr', StrPtr(origin), 'uptr', s)
						p := NumPut('ptr', ps, p)
					}
				} else p := 0
				NumPut('ptr', p, pallowedOrigins)
				return 0
			}
			SetAllowedOrigins(this, allowedOriginsCount, pallowedOrigins) {
				AllowedOrigins := []
				loop allowedOriginsCount
					AllowedOrigins.Push(StrGet(NumGet(pallowedOrigins, (A_Index - 1) * A_PtrSize, 'ptr')))
				return 0
			}
			__Delete(*) {
				for ptr in fnptrs
					CallbackFree(ptr)
			}
		}
	}
	class ClientCertificateCollection extends WebView2.List {
		static IID := '{ef5674d2-bcc3-11eb-8529-0242ac130003}'
		Count => (ComCall(3, this, 'uint*', &value := 0), value)
		GetValueAtIndex(index) => (ComCall(4, this, 'uint', index, 'ptr*', certificate := WebView2.ClientCertificate()), certificate)
	}
	class ClientCertificateRequestedEventArgs extends WebView2.Base {
		static IID := '{bc59db28-bcc3-11eb-8529-0242ac130003}'
		Host => (ComCall(3, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		Port => (ComCall(4, this, 'int*', &value := 0), value)
		IsProxy => (ComCall(5, this, 'int*', &value := 0), value)
		AllowedCertificateAuthorities => (ComCall(6, this, 'ptr*', value := WebView2.StringCollection()), value)
		MutuallyTrustedCertificates => (ComCall(7, this, 'ptr*', value := WebView2.ClientCertificateCollection()), value)
		SelectedCertificate {
			get => (ComCall(8, this, 'ptr*', value := WebView2.ClientCertificate()), value)
			set => ComCall(9, this, 'ptr', Value)
		}
		Cancel {
			get => (ComCall(10, this, 'int*', &value := 0), value)
			set => ComCall(11, this, 'int', Value)
		}
		Handled {
			get => (ComCall(12, this, 'int*', &value := 0), value)
			set => ComCall(13, this, 'int', Value)
		}
		GetDeferral() => (ComCall(14, this, 'ptr*', deferral := WebView2.Deferral()), deferral)
	}
	class DOMContentLoadedEventArgs extends WebView2.Base {
		static IID := '{16B1E21A-C503-44F2-84C9-70ABA5031283}'
		NavigationId => (ComCall(3, this, 'int64*', &navigationId := 0), navigationId)
	}
	class Deferral extends WebView2.Base {
		static IID := '{c10e7f7b-b585-46f0-a623-8befbf3e4ee0}'
		Complete() => ComCall(3, this)
	}
	class DevToolsProtocolEventReceivedEventArgs extends WebView2.Base {
		static IID := '{653c2959-bb3a-4377-8632-b58ada4e66c4}'
		ParameterObjectAsJson => (ComCall(3, this, 'ptr*', &parameterObjectAsJson := 0), CoTaskMem_String(parameterObjectAsJson))

		static IID_2 := '{2DC4959D-1494-4393-95BA-BEA4CB9EBD1B}'
		SessionId => (ComCall(4, this, 'ptr*', &sessionId := 0), CoTaskMem_String(sessionId))
	}
	class DevToolsProtocolEventReceiver extends WebView2.Base {
		static IID := '{b32ca51a-8371-45e9-9317-af021d080367}'
		/** @param {(sender: WebView2.DevToolsProtocolEventReceiver, args: WebView2.DevToolsProtocolEventReceivedEventArgs) => void} eventHandler */
		add_DevToolsProtocolEventReceived(eventHandler) => (ComCall(3, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2DevToolsProtocolEventReceivedEventHandler
		remove_DevToolsProtocolEventReceived(token) => ComCall(4, this, 'int64', token)
	}
	class DownloadOperation extends WebView2.Base {
		static IID := '{3d6b6cf2-afe1-44c7-a995-c65117714336}'
		/** @param {(sender: WebView2.DownloadOperation, args: IUnknown) => void} eventHandler */
		add_BytesReceivedChanged(eventHandler) => (ComCall(3, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2BytesReceivedChangedEventHandler
		remove_BytesReceivedChanged(token) => ComCall(4, this, 'int64', token)
		/** @param {(sender: WebView2.DownloadOperation, args: IUnknown) => void} eventHandler */
		add_EstimatedEndTimeChanged(eventHandler) => (ComCall(5, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2EstimatedEndTimeChangedEventHandler
		remove_EstimatedEndTimeChanged(token) => ComCall(6, this, 'int64', token)
		/** @param {(sender: WebView2.DownloadOperation, args: IUnknown) => void} eventHandler */
		add_StateChanged(eventHandler) => (ComCall(7, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2StateChangedEventHandler
		remove_StateChanged(token) => ComCall(8, this, 'int64', token)
		Uri => (ComCall(9, this, 'ptr*', &uri := 0), CoTaskMem_String(uri))
		ContentDisposition => (ComCall(10, this, 'ptr*', &contentDisposition := 0), CoTaskMem_String(contentDisposition))
		MimeType => (ComCall(11, this, 'ptr*', &mimeType := 0), CoTaskMem_String(mimeType))
		TotalBytesToReceive => (ComCall(12, this, 'int64*', &totalBytesToReceive := 0), totalBytesToReceive)
		BytesReceived => (ComCall(13, this, 'int64*', &bytesReceived := 0), bytesReceived)
		EstimatedEndTime => (ComCall(14, this, 'ptr*', &estimatedEndTime := 0), CoTaskMem_String(estimatedEndTime))
		ResultFilePath => (ComCall(15, this, 'ptr*', &resultFilePath := 0), CoTaskMem_String(resultFilePath))
		State => (ComCall(16, this, 'int*', &downloadState := 0), downloadState)	; COREWEBVIEW2_DOWNLOAD_STATE
		InterruptReason => (ComCall(17, this, 'int*', &interruptReason := 0), interruptReason)	; COREWEBVIEW2_DOWNLOAD_INTERRUPT_REASON
		Cancel() => ComCall(18, this)
		Pause() => ComCall(19, this)
		Resume() => ComCall(20, this)
		CanResume => (ComCall(21, this, 'int*', &canResume := 0), canResume)
	}
	class DownloadStartingEventArgs extends WebView2.Base {
		static IID := '{e99bbe21-43e9-4544-a732-282764eafa60}'
		DownloadOperation => (ComCall(3, this, 'ptr*', downloadOperation := WebView2.DownloadOperation()), downloadOperation)
		Cancel {
			get => (ComCall(4, this, 'int*', &cancel := 0), cancel)
			set => ComCall(5, this, 'int', Value)
		}
		ResultFilePath {
			get => (ComCall(6, this, 'ptr*', &resultFilePath := 0), CoTaskMem_String(resultFilePath))
			set => ComCall(7, this, 'wstr', Value)
		}
		Handled {
			get => (ComCall(8, this, 'int*', &handled := 0), handled)
			set => ComCall(9, this, 'int', Value)
		}
		GetDeferral() => (ComCall(10, this, 'ptr*', deferral := WebView2.Deferral()), deferral)
	}
	class Environment extends WebView2.Base {
		static IID := '{b96d755e-0319-4e92-a296-23436f46a1fc}'
		/** @returns {Promise<WebView2.Controller>} */
		CreateCoreWebView2ControllerAsync(parentWindow) => (ComCall(3, this, 'ptr', parentWindow, 'ptr', WebView2.AsyncHandler(&p, WebView2.Controller)), p.then(r => r.Fill()))
		CreateWebResourceResponse(content, statusCode, reasonPhrase, headers) => (ComCall(4, this, 'ptr', content, 'int', statusCode, 'wstr', reasonPhrase, 'wstr', headers, 'ptr*', response := WebView2.WebResourceResponse()), response)
		BrowserVersionString => (ComCall(5, this, 'ptr*', &versionInfo := 0), CoTaskMem_String(versionInfo))
		/** @param {(sender: WebView2.Environment, args: IUnknown) => void} eventHandler */
		add_NewBrowserVersionAvailable(eventHandler) => (ComCall(6, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2NewBrowserVersionAvailableEventHandler
		remove_NewBrowserVersionAvailable(token) => ComCall(7, this, 'int64', token)

		static IID_2 := '{41F3632B-5EF4-404F-AD82-2D606C5A9A21}'
		CreateWebResourceRequest(uri, method, postData, headers) => (ComCall(8, this, 'wstr', uri, 'wstr', method, 'ptr', postData, 'wstr', headers, 'ptr*', request := WebView2.WebResourceRequest()), request)

		static IID_3 := '{80a22ae3-be7c-4ce2-afe1-5a50056cdeeb}'
		/** @returns {Promise<WebView2.CompositionController>} */
		CreateCoreWebView2CompositionControllerAsync(parentWindow) => (ComCall(9, this, 'ptr', parentWindow, 'ptr', WebView2.AsyncHandler(&p, WebView2.CompositionController)), p)
		CreateCoreWebView2PointerInfo() => (ComCall(10, this, 'ptr*', pointerInfo := WebView2.PointerInfo()), pointerInfo)

		static IID_4 := '{20944379-6dcf-41d6-a0a0-abc0fc50de0d}'
		GetAutomationProviderForWindow(hwnd) => (ComCall(11, this, 'ptr', hwnd, 'ptr*', &provider := 0), ComValue(0xd, provider))

		static IID_5 := '{319e423d-e0d7-4b8d-9254-ae9475de9b17}'
		/** @param {(sender: WebView2.Environment, args: WebView2.BrowserProcessExitedEventArgs) => void} eventHandler */
		add_BrowserProcessExited(eventHandler) => (ComCall(12, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2BrowserProcessExitedEventHandler
		remove_BrowserProcessExited(token) => ComCall(13, this, 'int64', token)

		static IID_6 := '{e59ee362-acbd-4857-9a8e-d3644d9459a9}'
		CreatePrintSettings() => (ComCall(14, this, 'ptr*', printSettings := WebView2.PrintSettings()), printSettings)

		static IID_7 := '{43C22296-3BBD-43A4-9C00-5C0DF6DD29A2}'
		UserDataFolder => (ComCall(15, this, 'ptr*', &value := 0), CoTaskMem_String(value))

		static IID_8 := '{D6EB91DD-C3D2-45E5-BD29-6DC2BC4DE9CF}'
		/** @param {(sender: WebView2.Environment, args: IUnknown) => void} eventHandler */
		add_ProcessInfosChanged(eventHandler) => (ComCall(16, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2ProcessInfosChangedEventHandler
		remove_ProcessInfosChanged(token) => ComCall(17, this, 'int64', token)
		GetProcessInfos() => (ComCall(18, this, 'ptr*', value := WebView2.ProcessInfoCollection()), value)

		static IID_9 := '{f06f41bf-4b5a-49d8-b9f6-fa16cd29f274}'
		CreateContextMenuItem(label, iconStream, kind) => (ComCall(19, this, 'wstr', label, 'ptr', iconStream, 'int', kind, 'ptr*', item := WebView2.ContextMenuItem()), item)	; IStream*, COREWEBVIEW2_CONTEXT_MENU_ITEM_KIND

		static IID_10 := '{ee0eb9df-6f12-46ce-b53f-3f47b9c928e0}'
		CreateCoreWebView2ControllerOptions() => (ComCall(20, this, 'ptr*', options := WebView2.ControllerOptions()), options)
		/** @returns {Promise<WebView2.Controller>} */
		CreateCoreWebView2ControllerWithOptionsAsync(parentWindow, options) => (ComCall(21, this, 'ptr', parentWindow, 'ptr', options, 'ptr', WebView2.AsyncHandler(&p, WebView2.Controller)), p.then(r => r.Fill()))	; ICoreWebView2ControllerOptions
		/** @returns {Promise<WebView2.CompositionController>} */
		CreateCoreWebView2CompositionControllerWithOptionsAsync(parentWindow, options) => (ComCall(22, this, 'ptr', parentWindow, 'ptr', options, 'ptr', WebView2.AsyncHandler(&p, WebView2.CompositionController)), p)	; ICoreWebView2ControllerOptions

		static IID_11 := '{F0913DC6-A0EC-42EF-9805-91DFF3A2966A}'
		FailureReportFolderPath => (ComCall(23, this, 'ptr*', &value := 0), CoTaskMem_String(value))

		static IID_12 := '{F503DB9B-739F-48DD-B151-FDFCF253F54E}'
		CreateSharedBuffer(size) => (ComCall(24, this, 'uint64', size, 'ptr*', shared_buffer := WebView2.SharedBuffer()), shared_buffer)

		static IID_13 := '{af641f58-72b2-11ee-b962-0242ac120002}'
		/** @returns {Promise<WebView2.ProcessExtendedInfoCollection>} */
		GetProcessExtendedInfosAsync() => (ComCall(25, this, 'ptr', WebView2.AsyncHandler(&p, WebView2.ProcessExtendedInfoCollection)), p)

		static IID_14 := 'a5e9fad9-c875-59da-9bd7-473aa5ca1cef'
		/**
		 * @param {$FilePath} path 
		 * @param {WebView2.FILE_SYSTEM_HANDLE_PERMISSION} permission
		 */
		CreateWebFileSystemFileHandle(path, permission) => ComCall(26, this, 'wstr', path, 'int', permission, 'ptr*', value := WebView2.FileSystemHandle(), value)
		/**
		 * @param {$DirPath} path 
		 * @param {WebView2.FILE_SYSTEM_HANDLE_PERMISSION} permission
		 */
		CreateWebFileSystemDirectoryHandle(path, permission) => ComCall(27, this, 'wstr', path, 'int', permission, 'ptr*', value := WebView2.FileSystemHandle(), value)
		/** @param {Array<IUnknown>} objects */
		CreateObjectCollection(objects) {
			items := Buffer(A_PtrSize * len := objects.Length), p := items.Ptr
			for it in objects
				p := NumPut('ptr', it.Ptr, p)
			ComCall(28, this, 'uint', len, 'ptr', items, 'ptr*', objectCollection := WebView2.ObjectCollection())
			return objectCollection
		}
	}
	class EnvironmentOptions extends Buffer {
		/**
		 * @param {Object} opts Options used to create WebView2 Environment.
		 * @param {String} opts.AdditionalBrowserArguments Changes the behavior of the WebView.
		 * @param {Bool} opts.AllowSingleSignOnUsingOSPrimaryAccount The AllowSingleSignOnUsingOSPrimaryAccount property is used to enable single sign on with Azure Active Directory (AAD) and personal Microsoft Account (MSA) resources inside WebView.
		 * @param {String} opts.Language The default display language for WebView.
		 * @param {String} opts.TargetCompatibleBrowserVersion Specifies the version of the WebView2 Runtime binaries required to be compatible with your app.
		 * @param {Bool} opts.ExclusiveUserDataFolderAccess Whether other processes can create WebView2 from WebView2Environment created with the same user data folder and therefore sharing the same WebView browser process instance.
		 * @param {Bool} opts.IsCustomCrashReportingEnabled When IsCustomCrashReportingEnabled is set to TRUE, Windows won't send crash data to Microsoft endpoint.
		 * @param {Array} opts.CustomSchemeRegistrations Array of custom scheme registrations.
		 * @param {Bool} opts.EnableTrackingPrevention The EnableTrackingPrevention property is used to enable/disable tracking prevention feature in WebView2.
		 * @param {Bool} opts.AreBrowserExtensionsEnabled When AreBrowserExtensionsEnabled is set to true, new extensions can be added to user profile and used.
		 * @param {WebView2.CHANNEL_SEARCH_KIND} opts.ChannelSearchKind The ChannelSearchKind property is CoreWebView2ChannelSearchKind.MostStable by default and environment creation searches for a release channel on the machine from most to least stable using the first channel found. The default search order is: WebView2 Release -> Beta -> Dev -> Canary.
		 * @param {WebView2.RELEASE_CHANNELS} opts.ReleaseChannels OR operation(s) can be applied to multiple to create a mask. The default value is a mask of all the channels. By default, environment creation searches for channels from most to least stable, using the first channel found on the device.
		 * @param {WebView2.SCROLLBAR_STYLE} opts.ScrollBarStyle The ScrollBar style being set on the WebView2 Environment.
		 */
		__New(opts) {
			cbs := [
				; options
				QueryInterface, AddRef, Release,
				get_xxx_str.Bind('AdditionalBrowserArguments'), put_xxx,
				get_xxx_str.Bind('Language'), put_xxx,
				get_xxx_str.Bind('TargetCompatibleBrowserVersion'), put_xxx,
				get_xxx_int.Bind('AllowSingleSignOnUsingOSPrimaryAccount'), put_xxx,
				; options2
				QueryInterface, AddRef, Release,
				get_xxx_int.Bind('ExclusiveUserDataFolderAccess'), put_xxx,
				; options3
				QueryInterface, AddRef, Release,
				get_xxx_int.Bind('IsCustomCrashReportingEnabled'), put_xxx,
				; options4
				QueryInterface, AddRef, Release,
				GetCustomSchemeRegistrations, SetCustomSchemeRegistrations,
				; options5
				QueryInterface, AddRef, Release,
				get_xxx_int.Bind('EnableTrackingPrevention'), put_xxx,
				; options6
				QueryInterface, AddRef, Release,
				get_xxx_int.Bind('AreBrowserExtensionsEnabled'), put_xxx,
				; options7
				QueryInterface, AddRef, Release,
				get_xxx_int.Bind('ChannelSearchKind'), put_xxx,
				get_xxx_int.Bind('ReleaseChannels'), put_xxx,
				; options8
				QueryInterface, AddRef, Release,
				get_xxx_int.Bind('ScrollBarStyle'), put_xxx,
			]
			n := 8, i := 0
			super.__New((n + cbs.Length) * A_PtrSize)
			p_this := ObjPtr(this), p_unk := this.Ptr, p := p_unk + n * A_PtrSize
			mp := Map(), fnptrs := [], this.DefineProp('__Delete', { call: __Delete })
			for cb in cbs {
				if cb == QueryInterface
					NumPut('ptr', p, this, (i++) * A_PtrSize)
				p := NumPut('ptr', mp.Get(cb, 0) || mp[cb] := CallbackCreate(cb, , cb.MinParams || 2), p)
			}
			for _, p in mp
				fnptrs.Push(p)
			QueryInterface(this, riid, ppvObject) {
				static iids := Map(
					'{2FDE08A8-1E9A-4766-8C05-95A9CEB9D1C5}', 0,	; ICoreWebView2EnvironmentOptions
					'{FF85C98A-1BA7-4A6B-90C8-2B752C89E9E2}', 1,	; ICoreWebView2EnvironmentOptions2
					'{4A5C436E-A9E3-4A2E-89C3-910D3513F5CC}', 2,	; ICoreWebView2EnvironmentOptions3
					'{AC52D13F-0D38-475A-9DCA-876580D6793E}', 3,	; ICoreWebView2EnvironmentOptions4
					'{0AE35D64-C47F-4464-814E-259C345D1501}', 4,	; ICoreWebView2EnvironmentOptions5
					'{57D29CC3-C84F-42A0-B0E2-EFFBD5E179DE}', 5,	; ICoreWebView2EnvironmentOptions6
					'{C48D539F-E39F-441C-AE68-1F66E570BDC5}', 6,	; ICoreWebView2EnvironmentOptions7
					'{7c7ecf51-e918-5caf-853c-e9a2bcc27775}', 7,	; ICoreWebView2EnvironmentOptions8
				)
				DllCall("ole32.dll\StringFromGUID2", "ptr", riid, "ptr", buf := Buffer(78), "int", 39)
				if (index := iids.Get(iid := StrUpper(StrGet(buf)), -1)) >= 0 {
					ObjAddRef(p_this)
					NumPut('ptr', p_unk + index * A_PtrSize, ppvObject)
					return 0
				}
				NumPut('ptr', 0, ppvObject)
				return 0x80004002
			}
			AddRef(this) => ObjAddRef(p_this)
			Release(this) => ObjRelease(p_this)
			put_xxx(this, value) => 0
			get_xxx_str(prop, this, pvalue) {
				if opts.HasOwnProp(prop) {
					p := DllCall('ole32\CoTaskMemAlloc', 'uptr', s := StrLen(v := opts.%prop%) * 2 + 2, 'ptr')
					DllCall('RtlMoveMemory', 'ptr', p, 'ptr', StrPtr(v), 'uptr', s)
				} else p := 0
				return (NumPut('ptr', p, pvalue), 0)
			}
			get_xxx_int(prop, this, pvalue) {
				if opts.HasOwnProp(prop)
					v := opts.%prop%
				else switch prop {
					case 'EnableTrackingPrevention': v := true
					case 'ReleaseChannels': v := 15
					default: v := 0
				}
				return (NumPut('int', v, pvalue), 0)
			}
			GetCustomSchemeRegistrations(this, pcount, pschemeRegistrations) {
				if opts.HasOwnProp('CustomSchemeRegistrations') && (csrs := opts.CustomSchemeRegistrations).Length {
					NumPut('uint', csrs.Length, pcount)
					NumPut('ptr', p := DllCall('ole32\CoTaskMemAlloc', 'uptr', csrs.Length * A_PtrSize, 'ptr'), pschemeRegistrations)
					for csr in csrs
						ObjPtrAddRef(csr), p := NumPut('ptr', csr.Ptr, p)
				} else NumPut('uint', 0, pcount), NumPut('ptr', 0, pschemeRegistrations)
				return 0
			}
			SetCustomSchemeRegistrations(this, count, schemeRegistrations) => 0
			__Delete(*) {
				for ptr in fnptrs
					CallbackFree(ptr)
			}
		}
	}
	class ExecuteScriptResult extends WebView2.Base {
		static IID := '{0CE15963-3698-4DF7-9399-71ED6CDD8C9F}'
		Succeeded => (ComCall(3, this, 'int*', &value := 0), value)
		ResultAsJson => (ComCall(4, this, 'ptr*', &jsonResult := 0), CoTaskMem_String(jsonResult))
		TryGetResultAsString(&resultIsString?) => (ComCall(5, this, 'ptr*', &result := 0, 'int*', &resultIsString := 0), CoTaskMem_String(result))
		Exception => (ComCall(6, this, 'ptr*', exception := WebView2.ScriptException()), exception)
	}
	class File extends WebView2.Base {
		static IID := '{f2c19559-6bc1-4583-a757-90021be9afec}'
		Path => (ComCall(3, this, 'ptr*', &path := 0), CoTaskMem_String(path))
	}
	class FileSystemHandle extends WebView2.Base {
		static IID := '{c65100ac-0de2-5551-a362-23d9bd1d0e1f}'
		/** @type {WebView2.FILE_SYSTEM_HANDLE_KIND} */
		Kind => (ComCall(3, this, 'int*', &value := 0), value)
		Path => (ComCall(4, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		/** @type {WebView2.FILE_SYSTEM_HANDLE_PERMISSION} */
		Permission => (ComCall(5, this, 'int*', &value := 0), value)
	}
	class Frame extends WebView2.Base {
		static IID := '{f1131a5e-9ba9-11eb-a8b3-0242ac130003}'
		Name => (ComCall(3, this, 'ptr*', &name := 0), CoTaskMem_String(name))
		/** @param {(sender: WebView2.Frame, args: IUnknown) => void} eventHandler */
		add_NameChanged(eventHandler) => (ComCall(4, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2FrameNameChangedEventHandler
		remove_NameChanged(token) => ComCall(5, this, 'int64', token)
		AddHostObjectToScriptWithOrigins(name, object, originsArr*) {
			if originsCount := originsArr.Length {
				p := (origins := Buffer(originsCount * A_PtrSize)).Ptr
				loop originsCount
					p := NumPut('ptr', StrPtr(originsArr[A_Index]), p)
			}
			ComCall(6, this, 'wstr', name, 'ptr', ComVar(object), 'uint', originsCount, 'ptr', origins)	; LPCWSTR*
		}
		RemoveHostObjectFromScript(name) => ComCall(7, this, 'wstr', name)
		/** @param {(sender: WebView2.Frame, args: IUnknown) => void} eventHandler */
		add_Destroyed(eventHandler) => (ComCall(8, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2FrameDestroyedEventHandler
		remove_Destroyed(token) => ComCall(9, this, 'int64', token)
		IsDestroyed() => (ComCall(10, this, 'int*', &destroyed := 0), destroyed)

		static IID_2 := '{7a6a5834-d185-4dbf-b63f-4a9bc43107d4}'
		/** @param {(sender: WebView2.Frame, args: WebView2.NavigationStartingEventArgs) => void} eventHandler */
		add_NavigationStarting(eventHandler) => (ComCall(11, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2FrameNavigationStartingEventHandler
		remove_NavigationStarting(token) => ComCall(12, this, 'int64', token)
		/** @param {(sender: WebView2.Frame, args: WebView2.ContentLoadingEventArgs) => void} eventHandler */
		add_ContentLoading(eventHandler) => (ComCall(13, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2FrameContentLoadingEventHandler
		remove_ContentLoading(token) => ComCall(14, this, 'int64', token)
		/** @param {(sender: WebView2.Frame, args: WebView2.NavigationCompletedEventArgs) => void} eventHandler */
		add_NavigationCompleted(eventHandler) => (ComCall(15, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2FrameNavigationCompletedEventHandler
		remove_NavigationCompleted(token) => ComCall(16, this, 'int64', token)
		/** @param {(sender: WebView2.Frame, args: WebView2.DOMContentLoadedEventArgs) => void} eventHandler */
		add_DOMContentLoaded(eventHandler) => (ComCall(17, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2FrameDOMContentLoadedEventHandler
		remove_DOMContentLoaded(token) => ComCall(18, this, 'int64', token)
		/** @returns {Promise<String>} */
		ExecuteScriptAsync(javaScript) => (ComCall(19, this, 'wstr', javaScript, 'ptr', WebView2.AsyncHandler(&p, StrGet)), p)
		PostWebMessageAsJson(webMessageAsJson) => ComCall(20, this, 'wstr', webMessageAsJson)
		PostWebMessageAsString(webMessageAsString) => ComCall(21, this, 'wstr', webMessageAsString)
		/** @param {(sender: WebView2.Frame, args: WebView2.WebMessageReceivedEventArgs) => void} eventHandler */
		add_WebMessageReceived(eventHandler) => (ComCall(22, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2FrameWebMessageReceivedEventHandler
		remove_WebMessageReceived(token) => ComCall(23, this, 'int64', token)

		static IID_3 := '{b50d82cc-cc28-481d-9614-cb048895e6a0}'
		/** @param {(sender: WebView2.Frame, args: WebView2.PermissionRequestedEventArgs) => void} eventHandler */
		add_PermissionRequested(eventHandler) => (ComCall(24, this, 'ptr', eventHandler, 'int64*', &token := 0), token)	; ICoreWebView2FramePermissionRequestedEventHandler
		remove_PermissionRequested(token) => ComCall(25, this, 'int64', token)

		static IID_4 := '{188782DC-92AA-4732-AB3C-FCC59F6F68B9}'
		PostSharedBufferToScript(sharedBuffer, access, additionalDataAsJson) => ComCall(26, this, 'ptr', sharedBuffer, 'int', access, 'wstr', additionalDataAsJson)

		static IID_5 := '{99d199c4-7305-11ee-b962-0242ac120002}'
		FrameId => (ComCall(27, this, 'uint*', &id := 0), id)

		static IID_6 := '{0de611fd-31e9-5ddc-9d71-95eda26eff32}'
		/** @param {(sender: WebView2.Frame, args: WebView2.ScreenCaptureStartingEventArgs) => void} eventHandler */
		add_ScreenCaptureStarting(eventHandler) => (ComCall(28, this, 'ptr', eventHandler, 'int64*', &token := 0), token)
		remove_ScreenCaptureStarting(token) => ComCall(29, this, 'int64', token)
	}
	class FrameCreatedEventArgs extends WebView2.Base {
		static IID := '{4d6e7b5e-9baa-11eb-a8b3-0242ac130003}'
		Frame => (ComCall(3, this, 'ptr*', frame := WebView2.Frame()), frame)
	}
	class FrameInfo extends WebView2.Base {
		static IID := '{da86b8a1-bdf3-4f11-9955-528cefa59727}'
		Name => (ComCall(3, this, 'ptr*', &name := 0), CoTaskMem_String(name))
		Source => (ComCall(4, this, 'ptr*', &source := 0), CoTaskMem_String(source))

		static IID_2 := this.DefaultIID := '{56f85cfa-72c4-11ee-b962-0242ac120002}'
		ParentFrameInfo => (ComCall(5, this, 'ptr*', frameInfo := WebView2.FrameInfo()), frameInfo)
		FrameId => (ComCall(6, this, 'uint*', &id := 0), id)
		FrameKind => (ComCall(7, this, 'uint*', &kind := 0), kind)
	}
	class FrameInfoCollection extends WebView2.Base {
		static IID := '{8f834154-d38e-4d90-affb-6800a7272839}'
		GetIterator() => (ComCall(3, this, 'ptr*', iterator := WebView2.FrameInfoCollectionIterator()), iterator)
	}
	class FrameInfoCollectionIterator extends WebView2.Base {
		static IID := '{1bf89e2d-1b2b-4629-b28f-05099b41bb03}'
		HasCurrent => (ComCall(3, this, 'int*', &hasCurrent := 0), hasCurrent)
		GetCurrent() => (ComCall(4, this, 'ptr*', frameInfo := WebView2.FrameInfo()), frameInfo)
		MoveNext() => (ComCall(5, this, 'int*', &hasNext := 0), hasNext)
		__Enum(n) => (&fi, *) => this.HasCurrent && (fi := this.GetCurrent(), this.MoveNext(), true)
	}
	class Handler extends Buffer {
		/**
		 * Construct ICoreWebView2 Event or Completed Handler.
		 * @param invoke Invoke function of handler.
		 * The first parameter of the callback function is the event interface pointer.
		 * @see https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/#delegates
		 */
		static Call(invoke) {
			static pfns := [CallbackCreate(QueryInterface), CallbackCreate(AddRef), CallbackCreate(Release)]
				.DefineProp('__Delete', { call: __Delete })
			if HasMethod(invoke) {
				handler := super(6 * A_PtrSize)
				NumPut('ptr', handler.Ptr + 2 * A_PtrSize, 'ptr', ObjPtr(handler),
					'ptr', pfns[1], 'ptr', pfns[2], 'ptr', pfns[3],
					'ptr', CallbackCreate(invoke, , 3), handler)
				handler.__Delete := (this) => CallbackFree(NumGet(this, 5 * A_PtrSize, 'ptr'))
				return handler
			}
			return invoke
			QueryInterface(interface, riid, ppvObject) => 0x80004002
			AddRef(this) => ObjAddRef(NumGet(this, A_PtrSize, 'ptr'))
			Release(this) => ObjRelease(NumGet(this, A_PtrSize, 'ptr'))
			__Delete(this) {
				for p in this
					CallbackFree(p)
			}
		}
	}
	class HttpHeadersCollectionIterator extends WebView2.Base {
		static IID := '{0702fc30-f43b-47bb-ab52-a42cb552ad9f}'
		GetCurrentHeader(&name, &value) {
			ComCall(3, this, 'ptr*', &name := 0, 'ptr*', &value := 0)
			name := CoTaskMem_String(name), value := CoTaskMem_String(value)
		}
		HasCurrentHeader => (ComCall(4, this, 'int*', &hasCurrent := 0), hasCurrent)
		MoveNext() => (ComCall(5, this, 'int*', &hasNext := 0), hasNext)
		__Enum(n) => (&name, &value, *) => this.HasCurrentHeader && (this.GetCurrentHeader(&name, &value), this.MoveNext(), true)
	}
	class HttpRequestHeaders extends WebView2.Base {
		static IID := '{e86cac0e-5523-465c-b536-8fb9fc8c8c60}'
		GetHeader(name) => (ComCall(3, this, 'wstr', name, 'ptr*', &value := 0), CoTaskMem_String(value))
		GetHeaders(name) => (ComCall(4, this, 'wstr', name, 'ptr*', iterator := WebView2.HttpHeadersCollectionIterator()), iterator)
		RetVal(name) => (ComCall(5, this, 'wstr', name, 'int*', &RetVal := 0), RetVal)
		SetHeader(name, value) => ComCall(6, this, 'wstr', name, 'wstr', value)
		RemoveHeader(name) => ComCall(7, this, 'wstr', name)
		GetIterator() => (ComCall(8, this, 'ptr*', iterator := WebView2.HttpHeadersCollectionIterator()), iterator)
	}
	class HttpResponseHeaders extends WebView2.Base {
		static IID := '{03c5ff5a-9b45-4a88-881c-89a9f328619c}'
		AppendHeader(name, value) => ComCall(3, this, 'wstr', name, 'wstr', value)
		RetVal(name) => (ComCall(4, this, 'wstr', name, 'int*', &RetVal := 0), RetVal)
		GetHeader(name) => (ComCall(5, this, 'wstr', name, 'ptr*', &value := 0), CoTaskMem_String(value))
		GetHeaders(name) => (ComCall(6, this, 'wstr', name, 'ptr*', iterator := WebView2.HttpHeadersCollectionIterator()), iterator)
		GetIterator() => (ComCall(7, this, 'ptr*', iterator := WebView2.HttpHeadersCollectionIterator()), iterator)
	}
	class LaunchingExternalUriSchemeEventArgs extends WebView2.Base {
		static IID := '{07D1A6C3-7175-4BA1-9306-E593CA07E46C}'
		Uri => (ComCall(3, this, 'ptr*', value := 0), CoTaskMem_String(value))
		InitiatingOrigin => (ComCall(4, this, 'ptr*', value := 0), CoTaskMem_String(value))
		IsUserInitiated => (ComCall(5, this, 'int*', &value := 0), value)
		Cancel {
			get => (ComCall(6, this, 'int*', &value := 0), value)
			set => ComCall(7, this, 'int', Value)
		}
		GetDeferral() => (ComCall(8, this, 'ptr*', value := WebView2.Deferral()), value)
	}
	class MoveFocusRequestedEventArgs extends WebView2.Base {
		static IID := '{2d6aa13b-3839-4a15-92fc-d88b3c0d9c9d}'
		Reason => (ComCall(3, this, 'int*', &reason := 0), reason)	; COREWEBVIEW2_MOVE_FOCUS_REASON
		Handled {
			get => (ComCall(4, this, 'int*', &value := 0), value)
			set => ComCall(5, this, 'int', Value)
		}
	}
	class NavigationCompletedEventArgs extends WebView2.Base {
		static IID := '{30d68b7d-20d9-4752-a9ca-ec8448fbb5c1}'
		IsSuccess => (ComCall(3, this, 'int*', &isSuccess := 0), isSuccess)
		WebErrorStatus => (ComCall(4, this, 'int*', &webErrorStatus := 0), webErrorStatus)	; COREWEBVIEW2_WEB_ERROR_STATUS
		NavigationId => (ComCall(5, this, 'int64*', &navigationId := 0), navigationId)

		static IID_2 := '{FDF8B738-EE1E-4DB2-A329-8D7D7B74D792}'
		HttpStatusCode => (ComCall(6, this, 'int*', &http_status_code := 0), http_status_code)
	}
	class NavigationStartingEventArgs extends WebView2.Base {
		static IID := '{5b495469-e119-438a-9b18-7604f25f2e49}'
		Uri => (ComCall(3, this, 'ptr*', &uri := 0), CoTaskMem_String(uri))
		IsUserInitiated => (ComCall(4, this, 'int*', &isUserInitiated := 0), isUserInitiated)
		IsRedirected => (ComCall(5, this, 'int*', &isRedirected := 0), isRedirected)
		RequestHeaders => (ComCall(6, this, 'ptr*', requestHeaders := WebView2.HttpRequestHeaders()), requestHeaders)
		Cancel {
			get => (ComCall(7, this, 'int*', &cancel := 0), cancel)
			set => ComCall(8, this, 'int', Value)
		}
		NavigationId => (ComCall(9, this, 'int64*', &navigationId := 0), navigationId)

		static IID_2 := '{9086BE93-91AA-472D-A7E0-579F2BA006AD}'
		AdditionalAllowedFrameAncestors {
			get => (ComCall(10, this, 'ptr*', &value := 0), CoTaskMem_String(value))
			set => ComCall(11, this, 'wstr', Value)
		}

		static IID_3 := '{DDFFE494-4942-4BD2-AB73-35B8FF40E19F}'
		NavigationKind => (ComCall(12, this, 'int*', &navigation_kind := 0), navigation_kind)
	}
	class NewWindowRequestedEventArgs extends WebView2.Base {
		static IID := '{34acb11c-fc37-4418-9132-f9c21d1eafb9}'
		Uri => (ComCall(3, this, 'ptr*', &uri := 0), CoTaskMem_String(uri))
		NewWindow {
			set => ComCall(4, this, 'ptr', Value)
			get => (ComCall(5, this, 'ptr*', newWindow := WebView2.Core()), newWindow)
		}
		Handled {
			set => ComCall(6, this, 'int', Value)
			get => (ComCall(7, this, 'int*', &handled := 0), handled)
		}
		IsUserInitiated => (ComCall(8, this, 'int*', &isUserInitiated := 0), isUserInitiated)
		GetDeferral() => (ComCall(9, this, 'ptr*', deferral := WebView2.Deferral()), deferral)
		WindowFeatures => (ComCall(10, this, 'ptr*', value := WebView2.WindowFeatures()), value)

		static IID_2 := '{bbc7baed-74c6-4c92-b63a-7f5aeae03de3}'
		Name => (ComCall(11, this, 'ptr*', &value := 0), CoTaskMem_String(value))

		static IID_3 := '{842bed3c-6ad6-4dd9-b938-28c96667ad66}'
		OriginalSourceFrameInfo => (ComCall(12, this, 'ptr*', frameInfo := WebView2.FrameInfo()), frameInfo)
	}
	class NonClientRegionChangedEventArgs extends WebView2.Base {
		static IID := '{AB71D500-0820-4A52-809C-48DB04FF93BF}'
		RegionKind => (ComCall(3, this, 'int*', &value := 0), value)
	}
	class Notification extends WebView2.Base {
		static IID := '{B7434D98-6BC8-419D-9DA5-FB5A96D4DACD}'
		/** @param {(sender: WebView2.Notification, args: IUnknown) => void} eventHandler */
		add_CloseRequested(eventHandler) => (ComCall(3, this, 'ptr', eventHandler, 'int64*', &token := 0), token)
		remove_CloseRequested(token) => ComCall(4, this, 'int64', token)
		ReportShown() => ComCall(5, this)
		ReportClicked() => ComCall(6, this)
		ReportClosed() => ComCall(7, this)
		Body => (ComCall(8, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		Direction => ComCall(9, this, 'int*', &value := 0)
		Language => (ComCall(10, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		Tag => (ComCall(11, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		IconUri => (ComCall(12, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		Title => (ComCall(13, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		BadgeUri => (ComCall(14, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		BodyImageUri => (ComCall(15, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		ShouldRenotify => (ComCall(16, this, 'int*', &value := 0), value)
		RequiresInteraction => (ComCall(17, this, 'int*', &value := 0), value)
		IsSilent => (ComCall(18, this, 'int*', &value := 0), value)
		Timestamp => (ComCall(19, this, 'double*', &value := 0), value)
		GetVibrationPattern() {
			ComCall(20, this, 'uint*', &count := 0, 'ptr*', &pvi := 0)
			(vibrationPattern := []).Capacity := count
			loop count
				vibrationPattern.Push(NumGet(pvi, 'int64')), pvi += 8
			return vibrationPattern
		}
	}
	class NotificationReceivedEventArgs extends WebView2.Base {
		static IID := '{1512DD5B-5514-4F85-886E-21C3A4C9CFE6}'
		SenderOrigin => (ComCall(3, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		Notification => (ComCall(4, this, 'ptr*', value := WebView2.Notification()), value)
		Handled {
			set => ComCall(5, this, 'int', Value)
			get => (ComCall(6, this, 'int*', &value := 0), value)
		}
		GetDeferral() => (ComCall(7, this, 'ptr*', deferral := WebView2.Deferral()), deferral)
	}
	class ObjectCollection extends WebView2.ObjectCollectionView {
		static IID := '{5cfec11c-25bd-4e8d-9e1a-7acdaeeec047}'
		RemoveValueAtIndex(index) => ComCall(5, this, 'uint', index)
		InsertValueAtIndex(index, value) => ComCall(6, this, 'uint', index, 'ptr', value)
	}
	class ObjectCollectionView extends WebView2.List {
		static IID := '{0f36fd87-4f69-4415-98da-888f89fb9a33}'
		Count => (ComCall(3, this, 'uint*', &value := 0), value)
		GetValueAtIndex(index) => (ComCall(4, this, 'uint', index, 'ptr*', value := WebView2.Base()), value)
	}
	class PermissionRequestedEventArgs extends WebView2.Base {
		static IID := '{973ae2ef-ff18-4894-8fb2-3c758f046810}'
		Uri => (ComCall(3, this, 'ptr*', &uri := 0), CoTaskMem_String(uri))
		PermissionKind => (ComCall(4, this, 'int*', &permissionKind := 0), permissionKind)	; COREWEBVIEW2_PERMISSION_KIND
		IsUserInitiated => (ComCall(5, this, 'int*', &isUserInitiated := 0), isUserInitiated)
		State {
			get => (ComCall(6, this, 'int*', &state := 0), state)	; COREWEBVIEW2_PERMISSION_STATE
			set => ComCall(7, this, 'int', Value)
		}
		GetDeferral() => (ComCall(8, this, 'ptr*', deferral := WebView2.Deferral()), deferral)

		static IID_2 := '{74d7127f-9de6-4200-8734-42d6fb4ff741}'
		Handled {
			get => (ComCall(9, this, 'int*', &handled := 0), handled)
			set => ComCall(10, this, 'int', Value)
		}

		static IID_3 := '{e61670bc-3dce-4177-86d2-c629ae3cb6ac}'
		SavesInProfile {
			get => (ComCall(11, this, 'int*', &value := 0), value)
			set => ComCall(12, this, 'int', Value)
		}
	}
	class PermissionSetting extends WebView2.Base {
		static IID := '{792b6eca-5576-421c-9119-74ebb3a4ffb3}'
		PermissionKind => (ComCall(3, this, 'int*', &value := 0), value)	; COREWEBVIEW2_PERMISSION_KIND
		PermissionOrigin => (ComCall(4, this, 'int*', &value := 0), CoTaskMem_String(value))
		PermissionState => (ComCall(5, this, 'int*', &value := 0), value)	; COREWEBVIEW2_PERMISSION_STATE
	}
	class PermissionSettingCollectionView extends WebView2.List {
		static IID := '{f5596f62-3de5-47b1-91e8-a4104b596b96}'
		GetValueAtIndex(index) => (ComCall(3, this, 'ptr*', permissionSetting := WebView2.PermissionSetting()), permissionSetting)
		Count => (ComCall(4, this, 'uint*', &value := 0), value)
	}
	class PointerInfo extends WebView2.Base {
		static IID := '{e6995887-d10d-4f5d-9359-4ce46e4f96b9}'
		PointerKind {
			get => (ComCall(3, this, 'uint*', &pointerKind := 0), pointerKind)
			set => ComCall(4, this, 'uint', Value)
		}
		PointerId {
			get => (ComCall(5, this, 'uint*', &pointerId := 0), pointerId)
			set => ComCall(6, this, 'uint', Value)
		}
		FrameId {
			get => (ComCall(7, this, 'uint*', &frameId := 0), frameId)
			set => ComCall(8, this, 'uint', Value)
		}
		PointerFlags {
			get => (ComCall(9, this, 'uint*', &pointerFlags := 0), pointerFlags)
			set => ComCall(10, this, 'uint', Value)
		}
		PointerDeviceRect {
			get => (ComCall(11, this, 'ptr', pointerDeviceRect := WebView2.RECT()), pointerDeviceRect)
			set => (A_PtrSize = 8 ? ComCall(12, this, 'ptr', Value) : ComCall(12, this, 'int64', NumGet(Value, 'int64'), 'int64', NumGet(Value, 8, 'int64')))
		}
		DisplayRect {
			get => (ComCall(13, this, 'ptr', displayRect := WebView2.RECT()), displayRect)
			set => (A_PtrSize = 8 ? ComCall(14, this, 'ptr', Value) : ComCall(14, this, 'int64', NumGet(Value, 'int64'), 'int64', NumGet(Value, 8, 'int64')))
		}
		PixelLocation {
			get => (ComCall(15, this, 'int64*', &pixelLocation := 0), pixelLocation)
			set => ComCall(16, this, 'int64', Value)
		}
		HimetricLocation {
			get => (ComCall(17, this, 'int64*', &himetricLocation := 0), himetricLocation)
			set => ComCall(18, this, 'int64', Value)
		}
		PixelLocationRaw {
			get => (ComCall(19, this, 'int64*', &pixelLocationRaw := 0), pixelLocationRaw)
			set => ComCall(20, this, 'int64', Value)
		}
		HimetricLocationRaw {
			get => (ComCall(21, this, 'int64*', &himetricLocationRaw := 0), himetricLocationRaw)
			set => ComCall(22, this, 'int64', Value)
		}
		Time {
			get => (ComCall(23, this, 'uint*', &time := 0), time)
			set => ComCall(24, this, 'uint', Value)
		}
		HistoryCount {
			get => (ComCall(25, this, 'uint*', &historyCount := 0), historyCount)
			set => ComCall(26, this, 'uint', Value)
		}
		InputData {
			get => (ComCall(27, this, 'int*', &inputData := 0), inputData)
			set => ComCall(28, this, 'int', Value)
		}
		KeyStates {
			get => (ComCall(29, this, 'uint*', &keyStates := 0), keyStates)
			set => ComCall(30, this, 'uint', Value)
		}
		PerformanceCount {
			get => (ComCall(31, this, 'uint64*', &performanceCount := 0), performanceCount)
			set => ComCall(32, this, 'uint64', Value)
		}
		ButtonChangeKind {
			get => (ComCall(33, this, 'int*', &buttonChangeKind := 0), buttonChangeKind)
			set => ComCall(34, this, 'int', Value)
		}
		PenFlags {
			get => (ComCall(35, this, 'uint*', &penFLags := 0), penFLags)
			set => ComCall(36, this, 'uint', Value)
		}
		PenMask {
			get => (ComCall(37, this, 'uint*', &penMask := 0), penMask)
			set => ComCall(38, this, 'uint', Value)
		}
		PenPressure {
			get => (ComCall(39, this, 'uint*', &penPressure := 0), penPressure)
			set => ComCall(40, this, 'uint', Value)
		}
		PenRotation {
			get => (ComCall(41, this, 'uint*', &penRotation := 0), penRotation)
			set => ComCall(42, this, 'uint', Value)
		}
		PenTiltX {
			get => (ComCall(43, this, 'int*', &penTiltX := 0), penTiltX)
			set => ComCall(44, this, 'int', Value)
		}
		PenTiltY {
			get => (ComCall(45, this, 'int*', &penTiltY := 0), penTiltY)
			set => ComCall(46, this, 'int', Value)
		}
		TouchFlags {
			get => (ComCall(47, this, 'uint*', &touchFlags := 0), touchFlags)
			set => ComCall(48, this, 'uint', Value)
		}
		TouchMask {
			get => (ComCall(49, this, 'uint*', &touchMask := 0), touchMask)
			set => ComCall(50, this, 'uint', Value)
		}
		TouchContact {
			get => (ComCall(51, this, 'ptr', touchContact := WebView2.RECT()), touchContact)
			set => (A_PtrSize = 8 ? ComCall(52, this, 'ptr', Value) : ComCall(52, this, 'int64', NumGet(Value, 'int64'), 'int64', NumGet(Value, 8, 'int64')))
		}
		TouchContactRaw {
			get => (ComCall(53, this, 'ptr', touchContactRaw := WebView2.RECT()), touchContactRaw)
			set => (A_PtrSize = 8 ? ComCall(54, this, 'ptr', Value) : ComCall(54, this, 'int64', NumGet(Value, 'int64'), 'int64', NumGet(Value, 8, 'int64')))
		}
		TouchOrientation {
			get => (ComCall(55, this, 'uint*', &touchOrientation := 0), touchOrientation)
			set => ComCall(56, this, 'uint', Value)
		}
		TouchPressure {
			get => (ComCall(57, this, 'uint*', &touchPressure := 0), touchPressure)
			set => ComCall(58, this, 'uint', Value)
		}
	}
	class PrintSettings extends WebView2.Base {
		static IID := '{377f3721-c74e-48ca-8db1-df68e51d60e2}'
		Orientation {
			get => (ComCall(3, this, 'int*', &orientation := 0), orientation)
			set => ComCall(4, this, 'int', Value)
		}
		ScaleFactor {
			get => (ComCall(5, this, 'double*', &scaleFactor := 0), scaleFactor)
			set => ComCall(6, this, 'double', Value)
		}
		PageWidth {
			get => (ComCall(7, this, 'double*', &pageWidth := 0), pageWidth)
			set => ComCall(8, this, 'double', Value)
		}
		PageHeight {
			get => (ComCall(9, this, 'double*', &pageHeight := 0), pageHeight)
			set => ComCall(10, this, 'double', Value)
		}
		MarginTop {
			get => (ComCall(11, this, 'double*', &marginTop := 0), marginTop)
			set => ComCall(12, this, 'double', Value)
		}
		MarginBottom {
			get => (ComCall(13, this, 'double*', &marginBottom := 0), marginBottom)
			set => ComCall(14, this, 'double', Value)
		}
		MarginLeft {
			get => (ComCall(15, this, 'double*', &marginLeft := 0), marginLeft)
			set => ComCall(16, this, 'double', Value)
		}
		MarginRight {
			get => (ComCall(17, this, 'double*', &marginRight := 0), marginRight)
			set => ComCall(18, this, 'double', Value)
		}
		ShouldPrintBackgrounds {
			get => (ComCall(19, this, 'int*', &shouldPrintBackgrounds := 0), shouldPrintBackgrounds)
			set => ComCall(20, this, 'int', Value)
		}
		ShouldPrintSelectionOnly {
			get => (ComCall(21, this, 'int*', &shouldPrintSelectionOnly := 0), shouldPrintSelectionOnly)
			set => ComCall(22, this, 'int', Value)
		}
		ShouldPrintHeaderAndFooter {
			get => (ComCall(23, this, 'int*', &shouldPrintHeaderAndFooter := 0), shouldPrintHeaderAndFooter)
			set => ComCall(24, this, 'int', Value)
		}
		HeaderTitle {
			get => (ComCall(25, this, 'ptr*', &headerTitle := 0), CoTaskMem_String(headerTitle))
			set => ComCall(26, this, 'wstr', Value)
		}
		FooterUri {
			get => (ComCall(27, this, 'ptr*', &footerUri := 0), CoTaskMem_String(footerUri))
			set => ComCall(28, this, 'wstr', Value)
		}

		static IID_2 := '{CA7F0E1F-3484-41D1-8C1A-65CD44A63F8D}'
		PageRanges {
			get => (ComCall(29, this, 'ptr*', &value := 0), CoTaskMem_String(value))
			set => ComCall(30, this, 'wstr', Value)
		}
		PagesPerSide {
			get => (ComCall(31, this, 'int*', &value := 0), value)
			set => ComCall(32, this, 'int', Value)
		}
		Copies {
			get => (ComCall(33, this, 'int*', &value := 0), value)
			set => ComCall(34, this, 'int', Value)
		}
		Collation {
			get => (ComCall(35, this, 'int*', &value := 0), value)	; COREWEBVIEW2_PRINT_COLLATION
			set => ComCall(36, this, 'int', Value)
		}
		ColorMode {
			get => (ComCall(37, this, 'int*', &value := 0), value)	; COREWEBVIEW2_PRINT_COLOR_MODE
			set => ComCall(38, this, 'int', Value)
		}
		Duplex {
			get => (ComCall(39, this, 'int*', &value := 0), value)	; COREWEBVIEW2_PRINT_DUPLEX
			set => ComCall(40, this, 'int', Value)
		}
		MediaSize {
			get => (ComCall(41, this, 'int*', &value := 0), value)	; COREWEBVIEW2_PRINT_MEDIA_SIZE
			set => ComCall(42, this, 'int', Value)
		}
		PrinterName {
			get => (ComCall(43, this, 'ptr*', &value := 0), CoTaskMem_String(value))
			set => ComCall(44, this, 'wstr', Value)
		}
	}
	class ProcessExtendedInfo extends WebView2.Base {
		static IID := '{af4c4c2e-45db-11ee-be56-0242ac120002}'
		ProcessInfo => (ComCall(3, this, 'ptr*', processInfo := WebView2.ProcessInfo()), processInfo)
		AssociatedFrameInfos => (ComCall(3, this, 'ptr*', frames := WebView2.FrameInfoCollection()), frames)
	}
	class ProcessExtendedInfoCollection extends WebView2.List {
		static IID := '{32efa696-407a-11ee-be56-0242ac120002}'
		Count => (ComCall(3, this, 'uint*', &count := 0), count)
		GetValueAtIndex(index) => (ComCall(4, this, 'uint', index, 'ptr*', processInfo := WebView2.ProcessExtendedInfo()), processInfo)
	}
	class ProcessInfo extends WebView2.Base {
		static IID := '{84FA7612-3F3D-4FBF-889D-FAD000492D72}'
		ProcessId => (ComCall(3, this, 'int*', &value := 0), value)
		Kind => (ComCall(4, this, 'int*', &kind := 0), kind)	; COREWEBVIEW2_PROCESS_KIND
	}
	class ProcessInfoCollection extends WebView2.List {
		static IID := '{402B99CD-A0CC-4FA5-B7A5-51D86A1D2339}'
		Count => (ComCall(3, this, 'uint*', &count := 0), count)
		GetValueAtIndex(index) => (ComCall(4, this, 'uint', index, 'ptr*', processInfo := WebView2.ProcessInfo()), processInfo)
	}
	class Profile extends WebView2.Base {
		static IID := '{79110ad3-cd5d-4373-8bc3-c60658f17a5f}'
		ProfileName => (ComCall(3, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		IsInPrivateModeEnabled => (ComCall(4, this, 'int*', &value := 0), value)
		ProfilePath => (ComCall(5, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		DefaultDownloadFolderPath {
			get => (ComCall(6, this, 'ptr*', &value := 0), CoTaskMem_String(value))
			set => ComCall(7, this, 'wstr', Value)
		}
		PreferredColorScheme {
			get => (ComCall(8, this, 'int*', &value := 0), value)	; COREWEBVIEW2_PREFERRED_COLOR_SCHEME
			set => ComCall(9, this, 'int', Value)
		}

		static IID_2 := '{fa740d4b-5eae-4344-a8ad-74be31925397}'
		/** @returns {Promise<void>} */
		ClearBrowsingDataAsync(dataKinds) => (ComCall(10, this, 'int', dataKinds, 'ptr', WebView2.AsyncHandler(&p)), p)	; COREWEBVIEW2_BROWSING_DATA_KINDS
		/** @returns {Promise<void>} */
		ClearBrowsingDataInTimeRangeAsync(dataKinds, startTime, endTime) => (ComCall(11, this, 'int', dataKinds, 'double', startTime, 'double', endTime, 'ptr', WebView2.AsyncHandler(&p)), p)	; COREWEBVIEW2_BROWSING_DATA_KINDS
		/** @returns {Promise<void>} */
		ClearBrowsingDataAllAsync() => (ComCall(12, this, 'ptr', WebView2.AsyncHandler(&p)), p)

		static IID_3 := '{B188E659-5685-4E05-BDBA-FC640E0F1992}'
		PreferredTrackingPreventionLevel {
			get => (ComCall(13, this, 'int*', &value := 0), value)	; COREWEBVIEW2_TRACKING_PREVENTION_LEVEL
			set => ComCall(14, this, 'int', Value)
		}

		static IID_4 := '{8F4ae680-192e-4eC8-833a-21cfadaef628}'
		/** @returns {Promise<void>} */
		SetPermissionStateAsync(permissionKind, origin, state) => (ComCall(15, this, 'int', permissionKind, 'wstr', origin, 'int', state, 'ptr', WebView2.AsyncHandler(&p)), p)	; COREWEBVIEW2_PERMISSION_KIND,, COREWEBVIEW2_PERMISSION_STATE
		/** @returns {Promise<WebView2.PermissionSettingCollectionView>} */
		GetNonDefaultPermissionSettingsAsync() => (ComCall(16, this, 'ptr', WebView2.AsyncHandler(&p, WebView2.PermissionSettingCollectionView)), p)

		static IID_5 := '{2EE5B76E-6E80-4DF2-BCD3-D4EC3340A01B}'
		CookieManager => (ComCall(17, this, 'ptr*', cookieManager := WebView2.CookieManager()), cookieManager)

		static IID_6 := '{BD82FA6A-1D65-4C33-B2B4-0393020CC61B}'
		IsPasswordAutosaveEnabled {
			get => (ComCall(18, this, 'int*', &value := 0), value)
			set => ComCall(19, this, 'int', Value)
		}
		IsGeneralAutofillEnabled {
			get => (ComCall(20, this, 'int*', &value := 0), value)
			set => ComCall(21, this, 'int', Value)
		}

		static IID_7 := '{7b4c7906-a1aa-4cb4-b723-db09f813d541}'
		/** @returns {Promise<WebView2.BrowserExtension>} */
		AddBrowserExtensionAsync(extensionFolderPath) => (ComCall(22, this, 'wstr', extensionFolderPath, 'ptr', WebView2.AsyncHandler(&p, WebView2.BrowserExtension)), p)
		/** @returns {Promise<WebView2.BrowserExtensionList>} */
		GetBrowserExtensionsAsync() => (ComCall(23, this, 'ptr', WebView2.AsyncHandler(&p, WebView2.BrowserExtensionList)), p)

		static IID_8 := '{fbf70c2f-eb1f-4383-85a0-163e92044011}'
		Delete() => ComCall(24, this)
		/** @param {(sender: WebView2.Profile, args: IUnknown) => void} eventHandler */
		add_Deleted(eventHandler) => (ComCall(25, this, 'ptr', eventHandler, 'int64*', &token := 0), token)
		remove_Deleted(token) => ComCall(26, this, 'int64', token)
	}
	class ProcessFailedEventArgs extends WebView2.Base {
		static IID := '{8155a9a4-1474-4a86-8cae-151b0fa6b8ca}'
		ProcessFailedKind => (ComCall(3, this, 'int*', &processFailedKind := 0), processFailedKind)	; COREWEBVIEW2_PROCESS_FAILED_KIND

		static IID_2 := '{4dab9422-46fa-4c3e-a5d2-41d2071d3680}'
		Reason => (ComCall(4, this, 'int*', &reason := 0), reason)	; COREWEBVIEW2_PROCESS_FAILED_REASON
		ExitCode => (ComCall(5, this, 'int*', &exitCode := 0), exitCode)
		ProcessDescription => (ComCall(6, this, 'ptr*', &processDescription := 0), CoTaskMem_String(processDescription))
		FrameInfosForFailedProcess => (ComCall(7, this, 'ptr*', frames := WebView2.FrameInfoCollection()), frames)

		static IID_3 := '{ab667428-094d-5fd1-b480-8b4c0fdbdf2f}'
		FailureSourceModulePath => (ComCall(8, this, 'ptr*', &value := 0), CoTaskMem_String(value))
	}
	class RegionRectCollectionView extends WebView2.List {
		static IID := '{333353B8-48BF-4449-8FCC-22697FAF5753}'
		Count => (ComCall(3, this, 'uint*', &value := 0), value)
		GetValueAtIndex(index) => (ComCall(4, this, 'uint', index, 'ptr', value := WebView2.RECT()), value)
	}
	class SaveAsUIShowingEventArgs extends WebView2.Base {
		static IID := '{55902952-0e0d-5aaa-a7d0-e833cdb34f62}'
		ContentMimeType => (ComCall(3, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		Cancel {
			set => ComCall(4, this, 'int', Value)
			get => (ComCall(5, this, 'int*', &value := 0), value)
		}
		SuppressDefaultDialog {
			set => ComCall(6, this, 'int', Value)
			get => (ComCall(7, this, 'int*', &value := 0), value)
		}
		GetDeferral() => (ComCall(8, this, 'ptr*', deferral := WebView2.Deferral()), deferral)
		SaveAsFilePath {
			set => ComCall(9, this, 'wstr', Value)
			get => (ComCall(10, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		}
		AllowReplace {
			set => ComCall(11, this, 'int', Value)
			get => (ComCall(12, this, 'int*', &value := 0), value)
		}
		Kind {
			set => ComCall(13, this, 'int', Value)
			get => (ComCall(14, this, 'int*', &value := 0), value)
		}
	}
	class SaveFileSecurityCheckStartingEventArgs extends WebView2.Base {
		static IID := '{cf4ff1d1-5a67-5660-8d63-ef699881ea65}'
		CancelSave {
			get => (ComCall(3, this, 'int*', &value := 0), value)
			set => ComCall(4, this, 'int', Value)
		}
		DocumentOriginUri => (ComCall(5, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		FileExtension => (ComCall(6, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		FilePath => (ComCall(7, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		SuppressDefaultPolicy {
			get => (ComCall(8, this, 'int*', &value := 0), value)
			set => ComCall(9, this, 'int', Value)
		}
		GetDeferral() => (ComCall(10, this, 'ptr*', deferral := WebView2.Deferral()), deferral)
	}
	class ScreenCaptureStartingEventArgs extends WebView2.Base {
		static IID := '{892c03fd-aee3-5eba-a1fa-6fd2f6484b2b}'
		Cancel {
			get => (ComCall(3, this, 'int*', &value := 0), value)
			set => ComCall(4, this, 'int', Value)
		}
		Handled {
			get => (ComCall(5, this, 'int*', &value := 0), value)
			set => ComCall(6, this, 'int', Value)
		}
		OriginalSourceFrameInfo => (ComCall(7, this, 'ptr*', value := WebView2.FrameInfo()), value)
		GetDeferral() => (ComCall(8, this, 'ptr*', value := WebView2.Deferral()), value)
	}
	class ScriptDialogOpeningEventArgs extends WebView2.Base {
		static IID := '{7390bb70-abe0-4843-9529-f143b31b03d6}'
		Uri => (ComCall(3, this, 'ptr*', &uri := 0), CoTaskMem_String(uri))
		Kind => (ComCall(4, this, 'int*', &kind := 0), kind)	; COREWEBVIEW2_SCRIPT_DIALOG_KIND
		Message => (ComCall(5, this, 'ptr*', &message := 0), CoTaskMem_String(message))
		Accept() => ComCall(6, this)
		DefaultText => (ComCall(7, this, 'ptr*', &defaultText := 0), CoTaskMem_String(defaultText))
		ResultText {
			get => (ComCall(8, this, 'ptr*', &resultText := 0), CoTaskMem_String(resultText))
			set => ComCall(9, this, 'wstr', Value)
		}
		GetDeferral() => (ComCall(10, this, 'ptr*', deferral := WebView2.Deferral()), deferral)
	}
	class ScriptException extends WebView2.Base {
		static IID := '{054DAE00-84A3-49FF-BC17-4012A90BC9FD}'
		LineNumber => (ComCall(3, this, 'uint*', &value := 0), value)
		ColumnNumber => (ComCall(4, this, 'uint*', &value := 0), value)
		Name => (ComCall(5, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		Message => (ComCall(6, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		ToJson => (ComCall(7, this, 'ptr*', &value := 0), CoTaskMem_String(value))
	}
	class ServerCertificateErrorDetectedEventArgs extends WebView2.Base {
		static IID := '{012193ED-7C13-48FF-969D-A84C1F432A14}'
		ErrorStatus => (ComCall(3, this, 'int*', &value := 0), value)
		RequestUri => (ComCall(4, this, 'ptr*', &value := 0), CoTaskMem_String(value))
		ServerCertificate => (ComCall(5, this, 'ptr*', value := WebView2.Certificate()), value)
		Action {
			get => (ComCall(6, this, 'int*', &value := 0), value)	; COREWEBVIEW2_SERVER_CERTIFICATE_ERROR_ACTION
			set => ComCall(7, this, 'int', Value)
		}
		GetDeferral() => (ComCall(8, this, 'ptr*', deferral := WebView2.Deferral()), deferral)
	}
	class Settings extends WebView2.Base {
		static IID := '{e562e4f0-d7fa-43ac-8d71-c05150499f00}'
		IsScriptEnabled {
			get => (ComCall(3, this, 'int*', &isScriptEnabled := 0), isScriptEnabled)
			set => ComCall(4, this, 'int', Value)
		}
		IsWebMessageEnabled {
			get => (ComCall(5, this, 'int*', &isWebMessageEnabled := 0), isWebMessageEnabled)
			set => ComCall(6, this, 'int', Value)
		}
		AreDefaultScriptDialogsEnabled {
			get => (ComCall(7, this, 'int*', &areDefaultScriptDialogsEnabled := 0), areDefaultScriptDialogsEnabled)
			set => ComCall(8, this, 'int', Value)
		}
		IsStatusBarEnabled {
			get => (ComCall(9, this, 'int*', &isStatusBarEnabled := 0), isStatusBarEnabled)
			set => ComCall(10, this, 'int', Value)
		}
		AreDevToolsEnabled {
			get => (ComCall(11, this, 'int*', &areDevToolsEnabled := 0), areDevToolsEnabled)
			set => ComCall(12, this, 'int', Value)
		}
		AreDefaultContextMenusEnabled {
			get => (ComCall(13, this, 'int*', &enabled := 0), enabled)
			set => ComCall(14, this, 'int', Value)
		}
		AreHostObjectsAllowed {
			get => (ComCall(15, this, 'int*', &allowed := 0), allowed)
			set => ComCall(16, this, 'int', Value)
		}
		IsZoomControlEnabled {
			get => (ComCall(17, this, 'int*', &enabled := 0), enabled)
			set => ComCall(18, this, 'int', Value)
		}
		IsBuiltInErrorPageEnabled {
			get => (ComCall(19, this, 'int*', &enabled := 0), enabled)
			set => ComCall(20, this, 'int', Value)
		}

		static IID_2 := '{ee9a0f68-f46c-4e32-ac23-ef8cac224d2a}'
		UserAgent {
			get => (ComCall(21, this, 'ptr*', &userAgent := 0), CoTaskMem_String(userAgent))
			set => ComCall(22, this, 'wstr', Value)
		}

		static IID_3 := '{fdb5ab74-af33-4854-84f0-0a631deb5eba}'
		AreBrowserAcceleratorKeysEnabled {
			get => (ComCall(23, this, 'int*', &areBrowserAcceleratorKeysEnabled := 0), areBrowserAcceleratorKeysEnabled)
			set => ComCall(24, this, 'int', Value)
		}

		static IID_4 := '{cb56846c-4168-4d53-b04f-03b6d6796ff2}'
		IsPasswordAutosaveEnabled {
			get => (ComCall(25, this, 'int*', &value := 0), value)
			set => ComCall(26, this, 'int', Value)
		}
		IsGeneralAutofillEnabled {
			get => (ComCall(27, this, 'int*', &value := 0), value)
			set => ComCall(28, this, 'int', Value)
		}

		static IID_5 := '{183e7052-1d03-43a0-ab99-98e043b66b39}'
		IsPinchZoomEnabled {
			get => (ComCall(29, this, 'int*', &enabled := 0), enabled)
			set => ComCall(30, this, 'int', Value)
		}

		static IID_6 := '{11cb3acd-9bc8-43b8-83bf-f40753714f87}'
		IsSwipeNavigationEnabled {
			get => (ComCall(31, this, 'int*', &enabled := 0), enabled)
			set => ComCall(32, this, 'int', Value)
		}

		static IID_7 := '{488dc902-35ef-42d2-bc7d-94b65c4bc49c}'
		HiddenPdfToolbarItems {
			get => (ComCall(33, this, 'int*', &hidden_pdf_toolbar_items := 0), hidden_pdf_toolbar_items)	; COREWEBVIEW2_PDF_TOOLBAR_ITEMS
			set => ComCall(34, this, 'int', Value)
		}

		static IID_8 := '{9e6b0e8f-86ad-4e81-8147-a9b5edb68650}'
		IsReputationCheckingRequired {
			get => (ComCall(35, this, 'int*', &value := 0), value)
			set => ComCall(36, this, 'int', Value)
		}

		static IID_9 := '{0528A73B-E92D-49F4-927A-E547DDDAA37D}'
		IsNonClientRegionSupportEnabled {
			get => (ComCall(37, this, 'int*', &enabled := 0), enabled)
			set => ComCall(38, this, 'int', Value)
		}

	}
	class SharedBuffer extends WebView2.Base {
		static IID := '{B747A495-0C6F-449E-97B8-2F81E9D6AB43}'
		Size => (ComCall(3, this, 'uint64', &value := 0), value)
		Buffer => (ComCall(4, this, 'ptr*', &value := 0), value)
		OpenStream() => (ComCall(5, this, 'ptr*', value := WebView2.Stream()), value)
		FileMappingHandle => (ComCall(6, this, 'ptr*', &value := 0), value)
		Close() => ComCall(7, this)
	}
	class SourceChangedEventArgs extends WebView2.Base {
		static IID := '{31e0e545-1dba-4266-8914-f63848a1f7d7}'
		IsNewDocument => (ComCall(3, this, 'int*', &isNewDocument := 0), isNewDocument)
	}
	class Stream extends WebView2.Base {
		ToBuffer() {
			DllCall('shlwapi\IStream_Reset', 'ptr', this)
			DllCall('shlwapi\IStream_Size', 'ptr', this, 'uint64*', &sz := 0)
			DllCall('shlwapi\IStream_Read', 'ptr', this, 'ptr', buf := Buffer(sz), 'uint', sz)
			return buf
		}
		ToString(encoding := 'utf-8') => StrGet(this.ToBuffer(), encoding)
	}
	class StringCollection extends WebView2.List {
		static IID := '{f41f3f8a-bcc3-11eb-8529-0242ac130003}'
		Count => (ComCall(3, this, 'uint*', &value := 0), value)
		GetValueAtIndex(index) => (ComCall(4, this, 'uint', index, 'ptr*', &value := 0), CoTaskMem_String(value))
	}
	class WebMessageReceivedEventArgs extends WebView2.Base {
		static IID := '{0f99a40c-e962-4207-9e92-e3d542eff849}'
		Source => (ComCall(3, this, 'ptr*', &source := 0), CoTaskMem_String(source))
		WebMessageAsJson => (ComCall(4, this, 'ptr*', &webMessageAsJson := 0), CoTaskMem_String(webMessageAsJson))
		TryGetWebMessageAsString() => (ComCall(5, this, 'ptr*', &webMessageAsString := 0), CoTaskMem_String(webMessageAsString))

		static IID_2 := '{06fc7ab7-c90c-4297-9389-33ca01cf6d5e}'
		AdditionalObjects => (ComCall(6, this, 'ptr*', value := WebView2.ObjectCollectionView()), value)
	}
	class WebResourceRequest extends WebView2.Base {
		static IID := '{97055cd4-512c-4264-8b5f-e3f446cea6a5}'
		Uri {
			get => (ComCall(3, this, 'ptr*', &uri := 0), CoTaskMem_String(uri))
			set => ComCall(4, this, 'wstr', Value)
		}
		Method {
			get => (ComCall(5, this, 'ptr*', &method := 0), CoTaskMem_String(method))
			set => ComCall(6, this, 'wstr', Value)
		}
		Content {
			get => (ComCall(7, this, 'ptr*', content := WebView2.Stream()), content)
			set => ComCall(8, this, 'ptr', Value)
		}
		Headers => (ComCall(9, this, 'ptr*', headers := WebView2.HttpRequestHeaders()), headers)
	}
	class WebResourceRequestedEventArgs extends WebView2.Base {
		static IID := '{453e667f-12c7-49d4-be6d-ddbe7956f57a}'
		Request => (ComCall(3, this, 'ptr*', request := WebView2.WebResourceRequest()), request)
		Response {
			get => (ComCall(4, this, 'ptr*', response := WebView2.WebResourceResponse()), response)
			set => ComCall(5, this, 'ptr', Value)
		}
		GetDeferral() => (ComCall(6, this, 'ptr*', deferral := WebView2.Deferral()), deferral)
		ResourceContext => (ComCall(7, this, 'int*', &context := 0), context)	; COREWEBVIEW2_WEB_RESOURCE_CONTEXT

		static IID_2 := '{9C562C24-B219-4D7F-92F6-B187FBBADD56}'
		RequestedSourceKind => (ComCall(8, this, 'int*', &requestedSourceKind := 0), requestedSourceKind)	; COREWEBVIEW2_WEB_RESOURCE_REQUEST_SOURCE_KINDS
	}
	class WebResourceResponse extends WebView2.Base {
		static IID := '{aafcc94f-fa27-48fd-97df-830ef75aaec9}'
		Content {
			get => (ComCall(3, this, 'ptr*', content := WebView2.Stream()), content)
			set => ComCall(4, this, 'ptr', Value)
		}
		Headers => (ComCall(5, this, 'ptr*', headers := WebView2.HttpResponseHeaders()), headers)
		StatusCode {
			get => (ComCall(6, this, 'int*', &statusCode := 0), statusCode)
			set => ComCall(7, this, 'int', Value)
		}
		ReasonPhrase {
			get => (ComCall(8, this, 'ptr*', &reasonPhrase := 0), CoTaskMem_String(reasonPhrase))
			set => ComCall(9, this, 'wstr', Value)
		}
	}
	class WebResourceResponseReceivedEventArgs extends WebView2.Base {
		static IID := '{D1DB483D-6796-4B8B-80FC-13712BB716F4}'
		Request => (ComCall(3, this, 'ptr*', request := WebView2.WebResourceRequest()), request)
		Response => (ComCall(4, this, 'ptr*', response := WebView2.WebResourceResponseView()), response)
	}
	class WebResourceResponseView extends WebView2.Base {
		static IID := '{79701053-7759-4162-8F7D-F1B3F084928D}'
		Headers => (ComCall(3, this, 'ptr*', headers := WebView2.HttpResponseHeaders()), headers)
		StatusCode => (ComCall(4, this, 'int*', &statusCode := 0), statusCode)
		ReasonPhrase => (ComCall(5, this, 'ptr*', &reasonPhrase := 0), CoTaskMem_String(reasonPhrase))
		/** @returns {Promise<WebView2.Stream>} */
		GetContentAsync() => (ComCall(6, this, 'ptr', WebView2.AsyncHandler(&p, WebView2.Stream)), p)
	}
	class WindowFeatures extends WebView2.Base {
		static IID := '{5eaf559f-b46e-4397-8860-e422f287ff1e}'
		HasPosition => (ComCall(3, this, 'int*', &value := 0), value)
		HasSize => (ComCall(4, this, 'int*', &value := 0), value)
		Left => (ComCall(5, this, 'uint*', &value := 0), value)
		Top => (ComCall(6, this, 'uint*', &value := 0), value)
		Height => (ComCall(7, this, 'uint*', &value := 0), value)
		Width => (ComCall(8, this, 'uint*', &value := 0), value)
		ShouldDisplayMenuBar => (ComCall(9, this, 'int*', &value := 0), value)
		ShouldDisplayStatus => (ComCall(10, this, 'int*', &value := 0), value)
		ShouldDisplayToolbar => (ComCall(11, this, 'int*', &value := 0), value)
		ShouldDisplayScrollBars => (ComCall(12, this, 'int*', &value := 0), value)
	}
	;#endregion

	;#region structs
	class PHYSICAL_KEY_STATUS extends Buffer {
		__New() => super.__New(24)
		RepeatCount {
			get => NumGet(this, 'uint')
			set => NumPut('uint', Value, this)
		}
		ScanCode {
			get => NumGet(this, 4, 'uint')
			set => NumPut('uint', Value, this, 4)
		}
		IsExtendedKey {
			get => NumGet(this, 8, 'int')
			set => NumPut('int', Value, this, 8)
		}
		IsMenuKeyDown {
			get => NumGet(this, 12, 'int')
			set => NumPut('int', Value, this, 12)
		}
		WasKeyDown {
			get => NumGet(this, 16, 'int')
			set => NumPut('int', Value, this, 16)
		}
		IsKeyReleased {
			get => NumGet(this, 20, 'int')
			set => NumPut('int', Value, this, 20)
		}
	}
	class RECT extends Buffer {
		__New() => super.__New(16)
		left {
			get => NumGet(this, 'int')
			set => NumPut('int', Value, this)
		}
		top {
			get => NumGet(this, 4, 'int')
			set => NumPut('int', Value, this, 4)
		}
		right {
			get => NumGet(this, 8, 'int')
			set => NumPut('int', Value, this, 8)
		}
		bottom {
			get => NumGet(this, 12, 'int')
			set => NumPut('int', Value, this, 12)
		}
	}
	;#endregion

	;#region constants
	static BOUNDS_MODE := { USE_RAW_PIXELS: 0, USE_RASTERIZATION_SCALE: 1 }
	static BROWSER_PROCESS_EXIT_KIND := { NORMAL: 0, FAILED: 1 }
	static BROWSING_DATA_KINDS := { FILE_SYSTEMS: (1 << 0), INDEXED_DB: (1 << 1), LOCAL_STORAGE: (1 << 2), WEB_SQL: (1 << 3), CACHE_STORAGE: (1 << 4), ALL_DOM_STORAGE: (1 << 5), COOKIES: (1 << 6), ALL_SITE: (1 << 7), DISK_CACHE: (1 << 8), DOWNLOAD_HISTORY: (1 << 9), GENERAL_AUTOFILL: (1 << 10), PASSWORD_AUTOSAVE: (1 << 11), BROWSING_HISTORY: (1 << 12), SETTINGS: (1 << 13), ALL_PROFILE: (1 << 14), SERVICE_WORKERS: (1 << 15) }
	static CAPTURE_PREVIEW_IMAGE_FORMAT := { PNG: 0, JPEG: 1 }
	static CHANNEL_SEARCH_KIND := { MOST_STABLE: 0, LEAST_STABLE: 1 }
	static CLIENT_CERTIFICATE_KIND := { SMART_CARD: 0, PIN: 1, OTHER: 2 }
	static CONTEXT_MENU_ITEM_KIND := { COMMAND: 0, CHECK_BOX: 1, RADIO: 2, SEPARATOR: 3, SUBMENU: 4 }
	static CONTEXT_MENU_TARGET_KIND := { PAGE: 0, IMAGE: 1, SELECTED_TEXT: 2, AUDIO: 3, VIDEO: 4 }
	static COOKIE_SAME_SITE_KIND := { NONE: 0, LAX: 1, STRICT: 2 }
	static DEFAULT_DOWNLOAD_DIALOG_CORNER_ALIGNMENT := { TOP_LEFT: 0, TOP_RIGHT: 1, BOTTOM_LEFT: 2, BOTTOM_RIGHT: 3 }
	static DOWNLOAD_INTERRUPT_REASON := { NONE: 0, FILE_FAILED: 1, FILE_ACCESS_DENIED: 2, FILE_NO_SPACE: 3, FILE_NAME_TOO_LONG: 4, FILE_TOO_LARGE: 5, FILE_MALICIOUS: 6, FILE_TRANSIENT_ERROR: 7, FILE_BLOCKED_BY_POLICY: 8, FILE_SECURITY_CHECK_FAILED: 9, FILE_TOO_SHORT: 10, FILE_HASH_MISMATCH: 11, NETWORK_FAILED: 12, NETWORK_TIMEOUT: 13, NETWORK_DISCONNECTED: 14, NETWORK_SERVER_DOWN: 15, NETWORK_INVALID_REQUEST: 16, SERVER_FAILED: 17, SERVER_NO_RANGE: 18, SERVER_BAD_CONTENT: 19, SERVER_UNAUTHORIZED: 20, SERVER_CERTIFICATE_PROBLEM: 21, SERVER_FORBIDDEN: 22, SERVER_UNEXPECTED_RESPONSE: 23, SERVER_CONTENT_LENGTH_MISMATCH: 24, SERVER_CROSS_ORIGIN_REDIRECT: 25, USER_CANCELED: 26, USER_SHUTDOWN: 27, USER_PAUSED: 28, DOWNLOAD_PROCESS_CRASHED: 29 }
	static DOWNLOAD_STATE := { IN_PROGRESS: 0, INTERRUPTED: 1, COMPLETED: 2 }
	static FAVICON_IMAGE_FORMAT := { PNG: 0, JPEG: 1 }
	static FILE_SYSTEM_HANDLE_KIND := { FILE: 0, DIRECTORY: 1 }
	static FILE_SYSTEM_HANDLE_PERMISSION := { READ_ONLY: 0, READ_WRITE: 1 }
	static FRAME_KIND := { UNKNOWN: 0, MAIN_FRAME: 1, IFRAME: 2, EMBED: 3, OBJECT: 4 }
	static HOST_RESOURCE_ACCESS_KIND := { DENY: 0, ALLOW: 1, DENY_CORS: 2 }
	static KEY_EVENT_KIND := { KEY_DOWN: 0, KEY_UP: 1, SYSTEM_KEY_DOWN: 2, SYSTEM_KEY_UP: 3 }
	static MEMORY_USAGE_TARGET_LEVEL := { NORMAL: 0, LOW: 1 }
	static MOUSE_EVENT_KIND := { HORIZONTAL_WHEEL: 0x20e, LEFT_BUTTON_DOUBLE_CLICK: 0x203, LEFT_BUTTON_DOWN: 0x201, LEFT_BUTTON_UP: 0x202, LEAVE: 0x2a3, MIDDLE_BUTTON_DOUBLE_CLICK: 0x209, MIDDLE_BUTTON_DOWN: 0x207, MIDDLE_BUTTON_UP: 0x208, MOVE: 0x200, RIGHT_BUTTON_DOUBLE_CLICK: 0x206, RIGHT_BUTTON_DOWN: 0x204, RIGHT_BUTTON_UP: 0x205, WHEEL: 0x20a, X_BUTTON_DOUBLE_CLICK: 0x20d, X_BUTTON_DOWN: 0x20b, X_BUTTON_UP: 0x20c, NON_CLIENT_RIGHT_BUTTON_DOWN: 0xa4, NON_CLIENT_RIGHT_BUTTON_UP: 0xa5 }
	static MOUSE_EVENT_VIRTUAL_KEYS := { NONE: 0, LEFT_BUTTON: 0x1, RIGHT_BUTTON: 0x2, SHIFT: 0x4, CONTROL: 0x8, MIDDLE_BUTTON: 0x10, X_BUTTON1: 0x20, X_BUTTON2: 0x40 }
	static MOVE_FOCUS_REASON := { PROGRAMMATIC: 0, NEXT: 1, PREVIOUS: 2 }
	static NAVIGATION_KIND := { RELOAD: 0, BACK_OR_FORWARD: 1, NEW_DOCUMENT: 2 }
	static NON_CLIENT_REGION_KIND := { NOWHERE: 0, CLIENT: 1, CAPTION: 2, MINIMIZE: 8, MAXIMIZE: 9, LOSE: 20 }
	static PDF_TOOLBAR_ITEMS := { ITEMS_NONE: 0, ITEMS_SAVE: 0x1, ITEMS_PRINT: 0x2, ITEMS_SAVE_AS: 0x4, ITEMS_ZOOM_IN: 0x8, ITEMS_ZOOM_OUT: 0x10, ITEMS_ROTATE: 0x20, ITEMS_FIT_PAGE: 0x40, ITEMS_PAGE_LAYOUT: 0x80, ITEMS_BOOKMARKS: 0x100, ITEMS_PAGE_SELECTOR: 0x200, ITEMS_SEARCH: 0x400, ITEMS_FULL_SCREEN: 0x800, ITEMS_MORE_SETTINGS: 0x1000 }
	static PERMISSION_KIND := { UNKNOWN_PERMISSION: 0, MICROPHONE: 1, CAMERA: 2, GEOLOCATION: 3, NOTIFICATIONS: 4, OTHER_SENSORS: 5, CLIPBOARD_READ: 6, MULTIPLE_AUTOMATIC_DOWNLOADS: 7, FILE_READ_WRITE: 8, AUTOPLAY: 9, LOCAL_FONTS: 10, MIDI_SYSTEM_EXCLUSIVE_MESSAGES: 11, WINDOW_MANAGEMENT: 12 }
	static PERMISSION_STATE := { DEFAULT: 0, ALLOW: 1, DENY: 2 }
	static POINTER_EVENT_KIND := { ACTIVATE: 0x24b, DOWN: 0x246, ENTER: 0x249, LEAVE: 0x24a, UP: 0x247, UPDATE: 0x245 }
	static PREFERRED_COLOR_SCHEME := { AUTO: 0, LIGHT: 1, DARK: 2 }
	static PRINT_COLLATION := { DEFAULT: 0, COLLATED: 1, UNCOLLATED: 2 }
	static PRINT_COLOR_MODE := { DEFAULT: 0, COLOR: 1, GRAYSCALE: 2 }
	static PRINT_DIALOG_KIND := { BROWSER: 0, SYSTEM: 1 }
	static PRINT_DUPLEX := { DEFAULT: 0, ONE_SIDED: 1, TWO_SIDED_LONG_EDGE: 2, TWO_SIDED_SHORT_EDGE: 3 }
	static PRINT_MEDIA_SIZE := { DEFAULT: 0, CUSTOM: 1 }
	static PRINT_ORIENTATION := { PORTRAIT: 0, LANDSCAPE: 1 }
	static PRINT_STATUS := { SUCCEEDED: 0, PRINTER_UNAVAILABLE: 1, OTHER_ERROR: 2 }
	static PROCESS_FAILED_KIND := { BROWSER_PROCESS_EXITED: 0, RENDER_PROCESS_EXITED: 1, RENDER_PROCESS_UNRESPONSIVE: 2, FRAME_RENDER_PROCESS_EXITED: 3, UTILITY_PROCESS_EXITED: 4, SANDBOX_HELPER_PROCESS_EXITED: 5, GPU_PROCESS_EXITED: 6, PPAPI_PLUGIN_PROCESS_EXITED: 7, PPAPI_BROKER_PROCESS_EXITED: 8, UNKNOWN_PROCESS_EXITED: 9 }
	static PROCESS_FAILED_REASON := { UNEXPECTED: 0, UNRESPONSIVE: 1, TERMINATED: 2, CRASHED: 3, LAUNCH_FAILED: 4, OUT_OF_MEMORY: 5, PROFILE_DELETED: 6 }
	static PROCESS_KIND := { BROWSER: 0, RENDERER: 1, UTILITY: 2, SANDBOX_HELPER: 3, GPU: 4, PPAPI_PLUGIN: 5, PPAPI_BROKER: 6 }
	static RELEASE_CHANNELS := { NONE: 0, STABLE: 1, BETA: 2, DEV: 4, CANARY: 8 }
	static SAVE_AS_KIND := { DEFAULT: 0, HTML_ONLY: 1, SINGLE_FILE: 2, COMPLETE: 3 }
	static SAVE_AS_UI_RESULT := { SUCCESS: 0, INVALID_PATH: 1, FILE_ALREADY_EXISTS: 2, KIND_NOT_SUPPORTED: 3, CANCELLED: 4 }
	static SCRIPT_DIALOG_KIND := { ALERT: 0, CONFIRM: 1, PROMPT: 2, BEFOREUNLOAD: 3 }
	static SCROLLBAR_STYLE := { DEFAULT: 0, FLUENT_OVERLAY: 1 }
	static SERVER_CERTIFICATE_ERROR_ACTION := { ALWAYS_ALLOW: 0, CANCEL: 1, DEFAULT: 2 }
	static SHARED_BUFFER_ACCESS := { READ_ONLY: 0, READ_WRITE: 1 }
	static TEXT_DIRECTION_KIND := { DEFAULT: 0, LEFT_TO_RIGHT: 1, RIGHT_TO_LEFT: 2 }
	static TRACKING_PREVENTION_LEVEL := { NONE: 0, BASIC: 1, BALANCED: 2, STRICT: 3 }
	static WEB_ERROR_STATUS := { UNKNOWN: 0, CERTIFICATE_COMMON_NAME_IS_INCORRECT: 1, CERTIFICATE_EXPIRED: 2, CLIENT_CERTIFICATE_CONTAINS_ERRORS: 3, CERTIFICATE_REVOKED: 4, CERTIFICATE_IS_INVALID: 5, SERVER_UNREACHABLE: 6, TIMEOUT: 7, ERROR_HTTP_INVALID_SERVER_RESPONSE: 8, CONNECTION_ABORTED: 9, CONNECTION_RESET: 10, DISCONNECTED: 11, CANNOT_CONNECT: 12, HOST_NAME_NOT_RESOLVED: 13, OPERATION_CANCELED: 14, REDIRECT_FAILED: 15, UNEXPECTED_ERROR: 16, VALID_AUTHENTICATION_CREDENTIALS_REQUIRED: 17, VALID_PROXY_AUTHENTICATION_REQUIRED: 18 }
	static WEB_RESOURCE_CONTEXT := { ALL: 0, DOCUMENT: 1, STYLESHEET: 2, IMAGE: 3, MEDIA: 4, FONT: 5, SCRIPT: 6, XML_HTTP_REQUEST: 7, FETCH: 8, TEXT_TRACK: 9, EVENT_SOURCE: 10, WEBSOCKET: 11, MANIFEST: 12, SIGNED_EXCHANGE: 13, PING: 14, CSP_VIOLATION_REPORT: 15, OTHER: 16 }
	static WEB_RESOURCE_REQUEST_SOURCE_KINDS := { NONE: 0, DOCUMENT: 1, SHARED_WORKER: 2, SERVICE_WORKER: 4, ALL: 0Xffffffff }
	;#endregion
}
CoTaskMem_String(ptr) {
	s := StrGet(ptr), DllCall('ole32\CoTaskMemFree', 'ptr', ptr)
	return s
}
; Construction and deconstruction VARIANT struct
class ComVar extends Buffer {
	/**
	 * Construction VARIANT struct, `ptr` property points to the address, `__Item` property returns var's Value
	 * @param vVal Values that need to be wrapped, supports String, Integer, Double, Array, ComValue, ComObjArray
	 * ### example
	 * `var1 := ComVar('string'), MsgBox(var1[])`
	 * 
	 * `var2 := ComVar([1,2,3,4], , true)`
	 * 
	 * `var3 := ComVar(ComValue(0xb, -1))`
	 * @param vType Variant's type, VT_VARIANT(default)
	 * @param convert Convert AHK's array to ComObjArray
	 */
	static Call(vVal := 0, vType := 0xC, convert := false) {
		static size := 8 + 2 * A_PtrSize
		if vVal is ComVar
			return vVal
		var := super(size, 0), IsObject(vVal) && vType := 0xC
		var.ref := ref := ComValue(0x4000 | vType, var.Ptr + (vType = 0xC ? 0 : 8))
		if convert && (vVal is Array) {
			switch Type(vVal[1]) {
				case "Integer": vType := 3
				case "String": vType := 8
				case "Float": vType := 5
				case "ComValue", "ComObject": vType := ComObjType(vVal[1])
				default: vType := 0xC
			}
			ComObjFlags(ref[] := obj := ComObjArray(vType, vVal.Length), i := -1)
			for v in vVal
				obj[++i] := v
		} else ref[] := vVal
		if vType & 0xC
			var.IsVariant := 1
		return var
	}
	__Delete() => DllCall("oleaut32\VariantClear", "ptr", this)
	__Item {
		get => this.ref[]
		set => this.ref[] := Value
	}
	Type {
		get => NumGet(this, "ushort")
		set {
			if (!this.IsVariant)
				throw PropertyError("VarType is not VT_VARIANT, Type is read-only.", -2)
			NumPut("ushort", Value, this)
		}
	}
	static Prototype.IsVariant := 0
	static Prototype.ref := 0
}
/************************************************************************
 * @description Implements a javascript-like Promise
 * @author thqby
 * @date 2025/01/09
 * @version 1.0.10
 ***********************************************************************/

/**
 * Represents the completion of an asynchronous operation
 * @see {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise MDN doc}
 * @alias Promise<T=Any>
 */
class Promise {
	static Prototype.status := 'pending'
	/** @type {T} */
	static Prototype.result := ''
	static Prototype.thrown := false

	/**
	 * @param {(resolve [,reject]) => void} executor A callback used to initialize the promise. This callback is passed two arguments:
	 * a resolve callback used to resolve the promise with a value or the result of another promise,
	 * and a reject callback used to reject the promise with a provided reason or error.
	 * - resolve(data) => void
	 * - reject(err) => void
	 */
	__New(executor) {
		this.callbacks := []
		try
			(executor.MaxParams = 1) ? executor(resolve) : executor(resolve, reject)
		catch Any as e
			reject(e)
		resolve(value := '') {
			if value is Promise {
				if !ObjHasOwnProp(value, 'status') {
					if this !== value
						return value.onCompleted(resolve)
					this.status := 'rejected', this.result := ValueError('Chaining cycle detected for promise', -1)
				} else if this
					this.status := value.status, this.result := value.result
				else return
			} else if this
				this.status := 'fulfilled', this.result := value
			else return
			SetTimer(task.Bind(this), -1), this := 0
		}
		reject(reason?) {
			if !this
				return
			this.status := 'rejected', this.result := reason ?? Error(, -1)
			SetTimer(task.Bind(this), -1), this := 0
		}
		static task(this) {
			for cb in this.DeleteProp('callbacks')
				cb(this)
			else if !ObjHasOwnProp(this, 'thrown') && this.status == 'rejected' && this.thrown := true
				throw this.result
		}
	}
	; __Delete() => OutputDebug('del: ' ObjPtr(this) '`n')

	/**
	 * Attaches a callback that is invoked when the Promise is completed (fulfilled or rejected).
	 * @param {(value: Promise) => void} callback The callback to execute when the Promise is completed.
	 * @returns {void}
	 */
	onCompleted(callback) {
		ObjHasOwnProp(this, 'callbacks') ? this.callbacks.Push(callback) : nextTick(this, callback)
		static nextTick(this, callback) => SetTimer(() => callback(this), -1)
	}
	/**
	 * Attaches callbacks for the resolution and/or rejection of the Promise.
	 * @param {(value) => void} onfulfilled The callback to execute when the Promise is resolved.
	 * @param {(reason) => void} onrejected The callback to execute when the Promise is rejected.
	 * @returns {void}
	 */
	onSettled(onfulfilled, onrejected := Promise.throw) {
		this.onCompleted(val => (val.status == 'fulfilled' ? onfulfilled : onrejected)(val.result))
	}
	/**
	 * Attaches callbacks for the resolution and/or rejection of the Promise.
	 * @param {(value) => Any} onfulfilled The callback to execute when the Promise is resolved.
	 * @param {(reason) => Any} onrejected The callback to execute when the Promise is rejected.
	 * @returns {Promise} A Promise for the completion of which ever callback is executed.
	 */
	then(onfulfilled, onrejected := Promise.throw) {
		return Promise(executor)
		executor(resolve, reject) {
			this.onCompleted(task)
			task(p1) {
				try
					resolve((p1.status == 'fulfilled' ? onfulfilled : onrejected)(p1.result))
				catch Any as e
					reject(e)
			}
		}
	}
	/**
	 * Attaches a callback for only the rejection of the Promise.
	 * @param {(reason) => Any} onrejected The callback to execute when the Promise is rejected.
	 * @returns {Promise} A Promise for the completion of the callback.
	 */
	catch(onrejected) => this.then(val => val, onrejected)
	/**
	 * Attaches a callback that is invoked when the Promise is settled (fulfilled or rejected).
	 * The resolved value cannot be modified from the callback.
	 * @param {() => void} onfinally The callback to execute when the Promise is settled (fulfilled or rejected).
	 * @returns {Promise} A Promise for the completion of the callback.
	 */
	finally(onfinally) => this.then(
		val => (onfinally(), val),
		err => (onfinally(), (Promise.throw)(err))
	)
	/**
	 * Waits for a promise to be completed.
	 * @returns {T}
	 */
	await2(timeout := -1) {
		end := A_TickCount + timeout, old := Critical(0)
		while (pending := !ObjHasOwnProp(this, 'status')) && (timeout < 0 || A_TickCount < end)
			Sleep(1)
		Critical(old)
		if !pending && this.status == 'fulfilled'
			return this.result
		throw pending ? TimeoutError() : (this.thrown := true) && this.result
	}
	/**
	 * Waits for a promise to be completed.
	 * Wake up only when a system event or timeout occurs, which takes up less cpu time.
	 * @returns {T}
	 */
	await(timeout := -1) {
		static hEvent := DllCall('CreateEvent', 'ptr', 0, 'int', 1, 'int', 0, 'ptr', 0, 'ptr')
		static __del := { Ptr: hEvent, __Delete: this => DllCall('CloseHandle', 'ptr', this) }
		static msg := Buffer(4 * A_PtrSize + 16)
		t := A_TickCount, r := 258, old := Critical(0)
		while (pending := !ObjHasOwnProp(this, 'status')) && timeout &&
			(DllCall('PeekMessage', 'ptr', msg, 'ptr', 0, 'uint', 0, 'uint', 0, 'uint', 0) ||
				1 == r := DllCall('MsgWaitForMultipleObjects', 'uint', 1, 'ptr*', hEvent,
					'int', 0, 'uint', timeout, 'uint', 7423, 'uint'))
			Sleep(-1), (timeout < 0) || timeout := Max(timeout - A_TickCount + t, 0)
		Critical(old)
		if !pending && this.status == 'fulfilled'
			return this.result
		throw pending ? r == 0xffffffff ? OSError() : TimeoutError() : (this.thrown := true) && this.result
	}
	static throw() {
		throw this
	}
	/**
	 * Creates a new resolved promise for the provided value.
	 * @param value The value the promise was resolved.
	 * @returns {Promise} A new resolved Promise.
	 */
	static resolve(value) => { base: this.Prototype, result: value, status: 'fulfilled' }
	/**
	 * Creates a new rejected promise for the provided reason.
	 * @param reason The reason the promise was rejected.
	 * @returns {Promise} A new rejected Promise.
	 */
	static reject(reason) => Promise((_, reject) => reject(reason))
	/**
	 * Creates a Promise that is resolved with an array of results when all of the provided Promises
	 * resolve, or rejected when any Promise is rejected.
	 * @param {Array} promises An array of Promises.
	 * @returns {Promise<Array>} A new Promise.
	 */
	static all(promises) {
		return Promise(executor)
		executor(resolve, reject) {
			res := [], count := res.Length := promises.Length
			resolve2 := (index, val) => (res[index] := val, !--count && resolve(res))
			for val in promises {
				if val is Promise
					val.onSettled(resolve2.Bind(A_Index), reject)
				else resolve2(A_Index, val)
			} else resolve(res)
		}
	}
	/**
	 * Creates a Promise that is resolved with an array of results when all
	 * of the provided Promises resolve or reject.
	 * @param {Array} promises An array of Promises.
	 * @returns {Promise<Array<{status: String, result: Any}>>} A new Promise.
	 */
	static allSettled(promises) {
		return Promise(executor)
		executor(resolve, reject) {
			res := [], count := res.Length := promises.Length
			callback := (index, val) => (res[index] := { result: val.result, status: val.status }, !--count && resolve(res))
			for val in promises {
				if val is Promise
					val.onCompleted(callback.Bind(A_Index))
				else res[A_Index] := { result: val, status: 'fulfilled' }, !--count && resolve(res)
			} else resolve(res)
		}
	}
	/**
     * The any function returns a promise that is fulfilled by the first given promise to be fulfilled, or rejected with an AggregateError containing an array of rejection reasons if all of the given promises are rejected. It resolves all elements of the passed iterable to promises as it runs this algorithm.
     * @param {Array<Promise>} promises An array of Promises.
     * @returns {Promise} A new Promise.
     */
	static any(promises) {
		return Promise(executor)
		executor(resolve, reject) {
			errs := [], count := errs.Length := promises.Length
			reject2 := (index, err) => (errs[index] := err, !--count && (
				err := Error('All promises were rejected'), err.errors := errs, reject(err)))
			for val in promises
				val.onSettled(resolve, reject2.Bind(A_Index))
		}
	}
	/**
	 * Creates a Promise that is resolved or rejected when any of the provided Promises are resolved or rejected.
	 * @param {Array} promises An array of Promises.
	 * @returns {Promise} A new Promise.
	 */
	static race(promises) {
		return Promise(executor)
		executor(resolve, reject) {
			for val in promises
				if val is Promise
					val.onSettled(resolve, reject)
				else return resolve(val)
		}
	}
	static try(fn) {
		try {
			val := fn()
			return Promise.resolve(val)
		} catch Any as e
			return Promise.reject(e)
	}
	/**
	 * Creates a new Promise and returns it in an object, along with its resolve and reject functions. 
	 * @returns {{ promise: Promise, resolve: (data) => void, reject: (err) => void }}
	 */
	static withResolvers() {
		local resolvers := 0
		resolvers.promise := Promise((resolve, reject) => resolvers := { resolve: resolve, reject: reject })
		return resolvers
	}
}
;
; MemoryModule by Joachim Bauch (known also as fancycode)
;
; Compiled from unmodified source (https://github.com/fancycode/MemoryModule) to
; Executable Form (*.obj) then converted to Base64 using thqby's COFF Reader
; (https://github.com/thqby/ahk2_lib/blob/master/MCode/COFFReader.ahk) as
; modified from G33kDude's MCL.ahk (https://github.com/G33kDude/MCL.ahk). It is
; distributed here in accordance with MPL-2.0 section 3.2:
;
; > If You distribute Covered Software in Executable Form then:
; >
; > (a) such Covered Software must also be made available in Source Code
; >     Form, as described in Section 3.1, and You must inform recipients of
; >     the Executable Form how they can obtain a copy of such Source Code
; >     Form by reasonable means in a timely manner, at a charge no more
; >     than the cost of distribution to the recipient; and
; >
; > (b) You may distribute such Executable Form under the terms of this
; >     License, or sublicense it under different terms, provided that the
; >     license for the Executable Form does not attempt to limit or alter
; >     the recipients' rights in the Source Code Form under this License.
;
; This MemoryModule library is sublicensed as follows, except as would otherwise
; violate the terms of Joachim Bauch's original MemoryModule:
;
; Copyright (C) 2025 by Philip Taylor <GeekDudeAHK@Gmail.com> (known also as
; GeekDude, G33kDude)
;
; Permission to use, copy, modify, and/or distribute this software for any
; purpose with or without fee is hereby granted.
;
; THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
; REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
; AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
; INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
; LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
; OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
; PERFORMANCE OF THIS SOFTWARE
;

class MemoryModule {
    static module := MCodeLoader({
        64: {
            code: "
            ( LTrim Join
158f,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
            )", export: "
            ( LTrim Join
BuildImportTable,CopySections,FinalizeSection,FinalizeSections,MemoryCallEntryPoint,MemoryDefaultAlloc,MemoryDefaultFree
,MemoryDefaultFreeLibrary,MemoryDefaultGetProcAddress,MemoryDefaultLoadLibrary,MemoryFindResource,MemoryFindResourceEx,M
emoryFreeLibrary,MemoryGetProcAddress,MemoryLoadLibrary,MemoryLoadLibraryEx,MemoryLoadResource,MemoryLoadString,MemoryLo
adStringEx,MemorySizeofResource,_MemorySearchResourceEntry,__chkstk,_compare,_find,_wcsnicmp,bsearch,free,malloc,mbstowc
s,memcpy,memset,qsort,realloc,strtol,wcstombs
            )", import : "
            ( LTrim Join
kernel32:SetLastError,GetProcessHeap,HeapFree,VirtualProtect,IsBadReadPtr,HeapAlloc,GetNativeSystemInfo,VirtualFree,lstr
lenA,FreeLibrary,LoadLibraryA,VirtualAlloc,GetProcAddress,GetThreadLocale,__chkstk|msvcrt:free,malloc,wcstombs,memcpy,_w
csnicmp,realloc,strtol,qsort,bsearch,mbstowcs,memset
            )",
        }, 32: {
            code: "
            ( LTrim Join
10da,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
DMIIAgIFggQAi
            )", export: "
            ( LTrim Join
_BuildImportTable,_CheckSize,_FinalizeSection,_FinalizeSections,_MemoryCallEntryPoint,_MemoryDefaultAlloc,_MemoryDefault
Free,_MemoryDefaultFreeLibrary,_MemoryDefaultGetProcAddress,_MemoryDefaultLoadLibrary,_MemoryFindResource,_MemoryFindRes
ourceEx,_MemoryFreeLibrary,_MemoryGetProcAddress,_MemoryLoadLibrary,_MemoryLoadLibraryEx,_MemoryLoadResource,_MemoryLoad
String,_MemoryLoadStringEx,_MemorySizeofResource,__MemorySearchResourceEntry,__compare,__find,__wcsnicmp,_bsearch,_free,
_malloc,_mbstowcs,_memcpy,_memset,_qsort,_realloc,_strtol,_wcstombs
            )", import: "
            ( LTrim Join
kernel32:SetLastError,GetProcessHeap,HeapFree,GetNativeSystemInfo,VirtualAlloc,FreeLibrary,lstrlenA,IsBadReadPtr,GetThre
adLocale,VirtualProtect,HeapAlloc,LoadLibraryA,GetProcAddress,VirtualFree|msvcrt:free,wcstombs,memcpy,malloc,strtol,qsor
t,mbstowcs,memset,_wcsnicmp,realloc,bsearch
            )"
        }
    })

    /**
     * Loads a module from a Buffer
     *
     * @param {Buffer} buf The unloaded module
     * 
     * @return {Integer} pointer to a loaded module in memory
     */
    static LoadLibrary(buf) => A_PtrSize == 8
        ? DllCall(this.module["MemoryLoadLibrary"], "Ptr", buf, "Ptr", buf.Size, "Ptr")
        : DllCall(this.module["_MemoryLoadLibrary"], "Ptr", buf, "Ptr", buf.Size, "Cdecl Ptr")

    /**
     * Finds a function address inside a loaded module
     *
     * @param {Integer} hModule pointer to a loaded module in memory
     * @param {String} name name of the function to look for
     * 
     * @return {Integer} pointer to a function
     */
    static GetProcAddress(hModule, name) => A_PtrSize == 8
        ? DllCall(this.module["MemoryGetProcAddress"], "Ptr", hModule, "AStr", name, "Ptr")
        : DllCall(this.module["_MemoryGetProcAddress"], "Ptr", hModule, "AStr", name, "Cdecl Ptr")
}

/************************************************************************
 * @description Enhanced version of MCode, which can build machine code supporting import symbol,
 * multi-function export, using strings, setting global variables and other features.
 * @author thqby
 * @date 2024/12/29
 * @version 1.0.1
 ***********************************************************************/

class MCodeLoader extends Buffer {
	/**
	 * Build a c/c++ code buffer, retrieve the function address, and then call it with DllCall to get higher performance.
	 * @param {{32?:String|$Code, 64?:String|$Code, import?:String, export?:String}} configs 
	 * @param {Integer} bits Number of bits corresponding to the code to be loaded.
	 * The built code cannot be run when the bits are inconsistent with the current exe.
	 * @param {Map} import_fn_ptrs Fill in the import address table with the function address obtained by yourself.
	 * @typedef {Object} $Code
	 * @property {String} code Base64 format string.
	 * @property {Integer} size If the code is compressed by LZ, the value is the decompressed size.
	 * @property {String|Array<String>} export The comma-concatenated names that are sequentially associated with the export function.
	 * If not specified, it is named by serial number.
	 * @property {String} import Get the address of dll import symbols in sequence and fill them into the import address table.
	 * e.g. `dll1:fn1,fn2|dll2:fn3`
	 */
	__New(configs, bits := A_PtrSize * 8, import_fn_ptrs := Map()) {
		if !ObjHasOwnProp(configs, bits)
			throw ValueError('No matching machine code')
		import := prop('import'), export_ := prop('export'), configs := configs.%bits%
		if IsObject(configs)
			import := prop('import') || import, export_ := prop('export') || export_, configs := configs.code
		if n := RegExMatch(configs, '^[\da-f]{1,8},\K')
			this.Size := '0x' SubStr(configs, 1, --n - 1), lz_decompress(base64_decode(StrPtr(configs) + n * 2), this)
		else base64_decode(StrPtr(configs), this)

		; decode headers
		; .export: N, offset1, ..., offsetN; .import: N, extry offset; .reloc: offset1, offset2, ..., 0
		bptr := this.Ptr, cptr := bptr + this.Size, eptr := cptr--, exports := [], relocs := []
		loop read_int() {
			if eptr <= n := read_int() + bptr
				throw ValueError('unknown/corrupt code format')
			exports.Push(n)
		} else exports.Push(bptr)
		import_count := read_int()
		if import_count && eptr < import_count * 4 + import_entry := read_int() + bptr
			throw ValueError('unknown/corrupt code format')
		while n := read_int()
			if eptr <= n += bptr
				throw ValueError('unknown/corrupt code format')
			else relocs.Push(n)
		(n := eptr - cptr += 2) && DllCall('RtlZeroMemory', 'ptr', cptr, 'uptr', n)

		; relocation
		for n in relocs
			if eptr <= t := NumGet(n, 'ptr') + bptr
				throw ValueError('unknown/corrupt code format')
			else NumPut('ptr', t, n)

		; import symbols
		if import_count {
			tp := bits = 32 ? 'uint' : 'int64'
			import_fn_ptrs := _fn_ptrs := import_fn_ptrs.Get.Bind(import_fn_ptrs, , 0)
			if bits = A_PtrSize * 8
				import_fn_ptrs := ((f, n) => f(n) || DllCall('GetProcAddress', 'ptr', mod, 'astr', n, 'ptr')).Bind(import_fn_ptrs)
			for n in StrSplit(import || '', '|') {
				t := InStr(n, ':'), r := SubStr(n, 1, t - 1)
				if r = '?'
					import_fn_ptrs := _fn_ptrs
				else if !mod := DllCall('GetModuleHandle', 'str', r, 'ptr') || DllCall('LoadLibrary', 'str', r, 'ptr')
					throw OSError(,, r)
				for n in StrSplit(SubStr(n, t + 1), ',', ' ')
					if !cptr := import_fn_ptrs(n)
						throw ValueError('unknown import symbol',, r '\' n)
					else import_entry := NumPut(tp, cptr, import_entry), import_count--
			}
			if import_count
				throw ValueError('wrong number of import symbols', import_count)
		}

		if bits = A_PtrSize * 8 && !DllCall('VirtualProtect', 'ptr', bptr, 'uint', this.Size, 'uint', 0x40, 'uint*', 0)
			throw OSError()

		if export_ {
			if export_ is String
				export_ := StrSplit(export_, ',')
			t := exports, exports := Map()
			loop Min(export_.Length, t.Length)
				exports[export_[A_Index]] := t[A_Index]
		}
		this.DefineProp('__Item', { value: exports })
			.DefineProp('__Enum', { call: (*) => exports.__Enum() })

		static base64_decode(b64, buf := Buffer()) {
			if DllCall('crypt32\CryptStringToBinary', 'ptr', b64, 'uint', 0, 'uint', 1, 'ptr', 0, 'uint*', &sz := 0, 'ptr', 0, 'ptr', 0) &&
				DllCall('crypt32\CryptStringToBinary', 'ptr', b64, 'uint', 0, 'uint', 1, 'ptr', buf, 'uint*', buf.Size := sz, 'ptr', 0, 'ptr', 0)
				return buf
			throw OSError()
		}
		static lz_decompress(compressBuf, UncompressBuf) {
			DllCall('ntdll\RtlDecompressBuffer', 'ushort', 2, 'ptr', UncompressBuf, 'uint', UncompressBuf.Size,
				'ptr', compressBuf, 'uint', compressBuf.Size, 'uint*', &fuSize := 0, 'hresult')
			if UncompressBuf.Size != fuSize
				throw ValueError('unknown/corrupt code format')
		}
		prop(name) => ObjHasOwnProp(configs, name) && configs.%name%
		read_int() {
			n := NumGet(cptr--, 'uchar')
			switch n & 0xc0 {
				case 0x80: n := (n & 0x3f) << 8 | NumGet(cptr--, 'uchar')
				case 0xc0: n := (n & 0x3f) << 24 | NumGet(cptr--, 'uchar') << 16 | NumGet(cptr--, 'uchar') << 8 | NumGet(cptr--, 'uchar')
			}
			return n
		}
	}

	; Retrieve the export function address
	__Item[name] => 0
	; Enumeration of export function addresses
	__Enum(*) => 0
}
;
; WebView2Loader.dll (32-bit)
;
; Copyright (C) Microsoft Corporation. All rights reserved.
;
; Redistribution and use in source and binary forms, with or without
; modification, are permitted provided that the following conditions are
; met:
;
;    * Redistributions of source code must retain the above copyright
; notice, this list of conditions and the following disclaimer.
;    * Redistributions in binary form must reproduce the above
; copyright notice, this list of conditions and the following disclaimer
; in the documentation and/or other materials provided with the
; distribution.
;    * The name of Microsoft Corporation, or the names of its contributors 
; may not be used to endorse or promote products derived from this
; software without specific prior written permission.
;
; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
; A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
; OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
; SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
; LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
; DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
; THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
; OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;

WebView2Loader32() {
    base64 := '
    (
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
    )'
    base64 .= '
    (
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
    )'
    base64 .= '
    (
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
    )'
    base64 .= '
    (
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
    )'
    base64 .= '
    (
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
    )'
    base64 .= '
    (
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
wAEUwAHIxANa1MABEsFXwAEcwU0ZZAEQwK8AKMABwQNI1cQDaMQDiMABI8FzwAG2GsERwAEgwWXAAR/BW3AaARAmwUnAAcEHUN3AAQ/BN8ABwS1k4ABgZbQA
bOQCfOAA4Qmg4ACt4Uio4ADhFrTgAA7hRA3kCODgAOEPABsBELYl4RPgACThC+QBeOAAbivhHOAA4QXA4ADhEuSF4AAi4RocARAo4RLt4AAq4RHgABvhD+AA
4Vl6jOAAEeEQ4ADhU+VSrLXkAsDkBdzgAOEl8OAAweEREB0BEBnoBeVNX+VJ5T3lQOVJ5S8s4AcVAeAAX19iYXNlZINBFGABY2RlY2zgAGBwYXNjYcGNYAFz
DHRkYAGBAV9fdGgGaQEDgAFfX2ZhcwJ0ZQF2ZWN0b3ILxAThCGyFAV9fZWEEYmniCHdpZnRfVjFjCmIBMmgBM2IBcBB0cjY04AByZXMgdHJpY3RhAnVuAGFs
aWduZWQAQ6UCgRUgbmV3YQ0gAGRlbGV0ZQA9CWABPj7gYjwAACEVYAE9AAIhYABbXQDAAG9wZXJh4BPhBZYtYAThMCuANi0tYAAHYQFgAGFHLT4qAC9n4ADh
OsAIADzgB8AFAAo+4AAsYT8pAAB+XeAAXuE3YQaABnwAASpV4AMrYAAtYAAvYAAlq+EGgAY8AAgmYAF8YAACXmAAYHZmdGFiyGxlJ+FAdmJoAYElACcAYHR5
cGVvQmZBAgBgbG+AAiAAc3RhdGljIGcwdWFyZOMCQSBuZ91jAXZhNyAgYAJ1ATCgAj5gQzHDIgAFqwPgA2RlAGZhdWx0IGNvAm4FAyBjbG9zdXZyYxHhO2H4
B+QLyQdp/nTjK2MZ5Q/SA+YDQxezCEBgdmlydHWgH2QAaXNwbGFjZW2AZW50IG1hcOEb+GVoIFwQaQTSEPgBbwjBmARgY29weY8SghIAYHVkdCByZXQIdXJu
4hhgRUgA4GBSVFRJtxvWHvsAPw8FAQXxLLEq9CyhAABgIG9tbmkgsSFzaT0RH2DHEFMC+Qi9AVtdAWkdAGBtYW5hZ/xlZM8T/Bt8Ag8UPhZeEg/6BL8W3wJ1
GWR5bmGCbeAuaW5pdGlQP+B6ZXIgZiAC8Q21AfhhdGXwj3kJFAK5KS8G/zYdzwifAjUOPhPfAnYF+jpwdGhyZQCPZDv1RyAMIiKhYfcAY29fYRh3YWlgTjYB
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
    )'
    base64 .= '
    (
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
    )'
    base64 .= '
    (
VpUwAHMwABCAKWAV8AKqGbA2H1BpIXAAIiASViOwMDAAoDAAcAAJwGUwAFAQByAzsACQGvCt0Ro4MAEwAHAwALAwAExgPDAYMABgPvABP5WwAErwBEtzCBBP
8AQGUfACMAA2uKBwUQAAgAAwkAAwKsAAMNAAGPAAGFBxwQB4cgAAAIIATAAMsvAADACHAFwADLAADErQAAzgAAwQiAAui4AAAECOAACgAAZMQJAAVgAGMJ8A
FqIVAD6jAFasAA60AABUYMgAFucAbu4AVvF1ABbyABb0AC8AAwkAUKgxABAAKxAAPxAAK9YQCx0CSxAARxAAWwobAgEAAxZ0AQAomcgBADgAAyxzARELH6oj
AB8wABtgAANUDB9VHQBkgBd0gAGKgAGcVYABsoABwIAB0IAB4DWIJfSABQaAMwcARXYAZW50UmVnaXMMdGUBqoIHU2V0SQBuZm9ybWF0aURvboUKVW5yjBNX
AHJpdGVUcmFuFHNmAgoAACRDbG8gc2VLZXmDBkdlgHRWYWx1ZVeEDpBPcGVuAA5FeAEIwYAHUXVlcnmCEAMJAABDb1Rhc2tNgGVtQWxsb2NKBABGcmVlAEFE
VgBBUEkzMi5kbGBsAG9sZUQCCQBVqwA4gTgExABowAN4wAACiMAAV2ViVmllAHcyTG9hZGVyqYIO8B/AhCHAgBXAfFYZwJuACafAAMXAAO5BwkoBAAIAA8Ah
bQBwYXJlQnJvd4BzZXJWZXJzwEYAcwBDcmVhdGUQQ29yZcUWRW52YGlyb25tAEhbB1cgaXRoT3CBWHMAAQBKQXZhaWxhYgZsiguLG1N0cmluEGcARHWHcGR9
AQgAgHaUi7x3AQCqysAA2sAA6MAA+MAAoBB4AQAgwAA4wACqRsAAUsAAZsAAdsAAqorAAKTAALLAALzAAKrIwADawADswAD+wACsFHnAsMAAPsAAVMAAqm7A
AIjAAJ7AAKzAAKq8wADSwADowAD8wACgCHoBABrAACzAAKo+wABOwABgwABwwACqisAAlsAAosAAsMAAKrzAAOTAAPrAABJ7qAEAJmAAQmAAVGAAqmRgAHxg
AI5gAKBgAKqwYADGYADcYADyYACgDHwBAB5gACxgAKo4YABEYABYYABoYACqeGAAlmAAqmAAtmAAqsBgAM5gANxgAPhgAKoKACgaYAAyYABIYAD+WGAAfyd/
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
M5xgIawztDO8ADPEM8wz1DPcVWAi7OAh/CCZDOAgHFVgICzgHzxgH0zgHlxVYB5s4B18YB2MYB2cVeAcrGAcvOAbzGAb3EXgGuxgGvw0BKAZFBUgGSSgGDQg
GEQ1TAA1VDVcNWQ1bAA1dDV8NYQ1jAA1lDWcNaQ1rAA1tDW8NcQ1zAQ11GCU5DXsNfQANfw1BDYMNhQANhw2JDYsNjQANjw2RDZMNlQENlygumw2dDZ8ADaE
Now2lDacADakNqw2tDa8ADbENsw21DbcADbkNuw29Db8ADYENww3FDccEDckNyygvjw3RAA3TDdUN1w3ZAA3bDd0N3w3hAQ3jKCUnDekN6wBIJW8N8Q3zDfU
ADfcN+Q37Df0ADf8NwQ4DDgUADgcOCQ4LDg0EDg8OETghFQ4XAGgmGw4dDh8OIQEOIwgfJw4pDisFDi0YHzEYJvUONwBoHzsOPQ4/DgEADkMORQ5HDkkADks
OTQ5PDlEADlMOVQ5XDlkQDlsOXQ5fOCLjBA5lDmcYYFAAQD+0OA6/3T/dP90/3T/dP90Ae10GDcgNyg3MAA3ODdAN0g3UAA3WDdgN2g3cAA3eDeAN4g3kAA3
mDegN6g3sAA3uDfAN8g30BA32DfgILTwN/gANwA4CDgQOBhQOCA4KOCqOOC1SAA4UDhYOGA4aAA4cDh4OIA4iEA4kDiYOKCwVrARMFzAOMjQVtg44AA46Djw
OPg4AAA5CDkQORg5IAA5KDkwOTg5QAA5SDlQOVg5YAA5aDlwOXg5gAA5iDmQOZg5oAHwXrA5uDnAOcgAOdA52DngOegAOfA5+DkAOggAOhA6GDogOigUOjCw
gkCQglA6WAA6YDpoOnA6eAA6gDqIOpA6mAA6oDqoOrA6uAA6wDoAUAEAYEFgHco0zjTSEIDcAdB07D30Pfw9BAA+DD4UPhw+JAFwdTQ+PD5EPkwAPlQ+XD5k
PmwAPnQ+fD6EPowQPpQ+nDCHrD60AD68PoA/hD+IAD+MP5A/oD+kQD+oP6w/sDFnYAOwY2AAvDHAMcQxgMgxzDFcMmD0YEpE0BlM8BlUNlWMFEA7GDsoOyyw
dkwQO1w7YNB2dDt4ADuAO5g7qDusADu8O8A7xDvIADvQO+g7+Dv8ADsMPBA8GDwwADxAPEQ8VDxYsDxcPGRQecAGcDMNRpTQjlFmtDK4MEeQFD200ILIsA34
PQAQPgg+ENINMD44BXYNaJINiD6oPsgAPtQ+7D7wPgwAPxA/MD9cP2gEP5xQDcA/yD/UITENgAEAaGAACDAAKDAwMDgwRDAAdDB4MIAwiDAAkDCUMJwwsDAo
0DDYEHL48nEUMQA4MUQxTDF0MQB4MZQxmDG0MaC4Mdgx+LByOLBxCngwCrhQgPgyGDOoODNYkHCYcDXYsDRQGDQAkHMGWFAvmFUQL7jQLuAQR/AwRxBV8EbQ
ECv8MCsEUCsMVXArFJArHJArLLArNEXQKzzwK0Q3ZLA/qFEQP+w4DBAlPDAlRFVQJUxwJVRwJWQxPbDoAQAM4YEwQQAPAA8A/w8ADwAPAA8ADwAPAA8ADwD/
DwAPAA8ADwAPAA8ADwAPAAkPANgnQAACAgAwAIInywYJKoZIAIb3DQEHAqCCBCe8IAG4AgEBMQAPMA0GCWCGSAABZQMEAgEFAAAwXAYKKwYBBAABgjcCAQSg
ThAwTDAXGAEPMAkAAwEAoASiAoAIADAxvAMEIKLmABbxFHhmLVF0AKgsVLUavrIbAI7Nkqkz5aEjALGxu3WwQKCCAA12MIIF9DCCAAPcoAMCAQICABMzAAAD
PmM64Ia/QXPXoLPRAGEFCcQKAQsgCX4xCzAACQYDVQQGEwJAVVMxEzARwQAIABMKV2FzaGluAGd0b24xEDAOAUEBBxMHUmVkbYBvbmQxHjAcEQEAChMVTWlj
cm8Ac29mdCBDb3JAcG9yYXRpEAMoRDAm8QEDEx/5AWRAZSBTaWduUAUgAFBDQSAyMDExADAeFw0yMzAyLDE20ACgN1rgADQwyDEzMeQAMHT/Cf8Jb/8J/wn6
CfQBA/8B8gEwGIIBIokS8BcDggECD7AeAQoCggEBAACK8C8PNjINAPTJx80WSO7wAMWuhtvay1JLANVaSDOYMY2KAOWEGWA9DV/LAIci2OSubVrzANcFcA34
+nJ1ADo1Xd5iQHb1AD5YB8tDUvLfAPAUbuzOZhHsACgAPivM+mjOAHXyjen6h+5zAC8lWiXfGKZIAIM/E5z0B0RTAIaU/3335zRvAHj1iuLSGo1vAL6de57R
RFoZAFxIE7qlcKT4AGHn7DNDop0aAIgfZNNu0P2QAKaj0ulOddlkAHkPiEHM0w80ABhw3Xk8RZIBAL8fbAorEz1TAA0YqQth/v9nANFpJcryx6bmADF40Vfa
    )'
    base64 .= '
    (
TdeKAJ2oinOEQKIxAJY1uC33iDzwADrZ6pCp85K3ANGYzGN9HeHwAFq+KmI9hmaEBNcCgCoBo4IBcxEQEW8wH7AUHSUECBgwFtYsCgMVBgIIsAAFBQcDAzAC
HQECDgQWBBQxAGM/0I+hf8qWAKsma+B0/Z0eINUGCTBF4QERBIA+MDykOjA4xRlGC88ZwxsWMBTxAQVCE5MjNys1MBAjNQVjCCNhCIAUSG5kAOVQBdOCqhc3
ADcitW2oynUCCJUwVAECHwRNMABLMEmgR6BFhgBDaHR0cDovLyB3d3cubbUGLmMAb20vcGtpb3DAcy9jcmwvQAigKxeAKzArIStfQQAtMAW9ADctMDguY3Js
ADBhBggrBgEFAAUHAQEEVTBTBDBRBXgwAoZFaAB0dHA6Ly93dwB3Lm1pY3JvcwBvZnQuY29tLwBwa2lvcHMvYwBlcnRzL01pYwBDb2RTaWdQQ0BBMjAxMV8B
CC0CMATEdDAMBgNVAB0TAQH/BAIwAAAwDQYJKoZIAIb3DQEBCwUAAAOCAgEAJ70iACL0lSsgAH3KAJDouIaTPm0TAIKvJjXcHhfiAMeclyrTtNmjAAZNFX8Q
9uzAAIfDNXwhpXvMAFMpJpSYuW5kANfJLvTSsVdgAFwdjlU/KveoAP7urtT9FcQVAOZW4yrpYOEwAGty5M+56HPVAByKvAdWSSnmAN1o0AGaiVd1ANwAtNry
B83WAF1JOGuA3DgwAPIxqiJIN5UtAAOXtMgoonnYAAm8fU0FzvlZALwT0lHKQbE3AKhWMMKZZHFRAIzrMcXD1SgdAHBPRbKxZruOANEkcqFAKwXuACCbKQxF
o3fTAA8K7jB9+nvmAIhVk7ygGANoAMhCWHvwuNL3AJNRmqaew+TeAFFW+sYW1BphAAICIsEjKpp5ALwyC6nD9xLcACQzDfTAnuu3AAzFAnTdfHdsAFaAN6XG
BRpTAE4TvwFvJN2UAEgTg6htNSdFAHpEB3HCBwJLAC3Y2fZoA+7bAFqh5FJ29NgfAOAjPZkaBVpNAEhZ/gYcYo9IAPhNWHlB5kYEADCayu4EmfijAPeOfpzE
Et7bAMO09t/ZPefVAGr4+UQOzr0kAN9VzkqTjBdkAMgc1ERMmhPtAK2/hXNDJbGeAOayTb++vMinADZHjU9/dWVGABkuTAS0+fDHANZm1rFOdWfAAHbQAgb4
RFhrANScdfu43jmZAMW0iPgqZe/UAIk73mqVOOwWAKdsM8c5bqA7AP2yHP8lpx8YAGNkEQ81wCCjAKMPoAEXc46dACpPKdt+HXGoAML3wIANMIIHAHowggVi
oAMCAAECAgphDpDSCgABAAMMizCBiDEICzAJgJMEBhMCQFVTMRMwEQEDCAATCldhc2hpbgBndG9uMRAwDgEBBQcTB1JlZG2Ab25kMR4wHEEEGAoTFYCqQ7Eg
Q2+AcnBvcmF0aUAMiDIwMMEHAxMpxwcYUm9vAAnAt2lmaQBjYXRlIEF1dIBob3JpdHkggbcQMB4XDUABNzA4ADIwNTkwOVoXSA0yNoIDMTCBAzBGfn8qUCoo
MCZDKh9RyQdkZSBA325AFSCjgODDJ4ICIklPAYLaJA8AwAUKAsHcq/AA+nIQHC6t2G4AqoIQTTS68rYAWCGfQhsqa+kAWlCquAY4GgQASbp/wwwe3TcAa8YS
2AvwOMIAmQawyDnVARQAMULTiQ15ZIcAfpRgJGyvnkkAnOloXtLfm1MAsgosw6/ZqSsArnoJr9eWWcoAYBoF6WZ26DIAUiYSL+erCFAAz7NEt13YxC4AA3Wr
aPPLbfMAOlyhFvRGuuAAOGSsbmQ1eKYAoGMPLdNAk/gA494HDdVceaUASSnnDb6gE3cAvpQ97/vjK1oAEB9NViiienIA4BI6t0le2O0A7UORg9l7snsAhhvZ
PrGMXegAiU+EGvKhL1kA5JA7La4zWMUAtz7+MtOzAz0AsbKvkjh+0p0AgCz1TlaRITUAJcM5bmR/U7oAnA+tGSOEy/QAugOGjfdf8NAAUr+MlIe8wCEAdCVf
GCi2zCcAKDglmDlKNs8AfLGSrhwjp6kAZuxhH2rhKEkAnV+I4iVd0yEASz5SxLVXPyQAA/DRelsv1SMA43BdD1FGd7MA+ADhvKwCgl8A28AVs70b1FUAS+c5
oQ/pI0kAvBi4RHxF5MEAw3J64HLnJN8Av0aZxe/CHFcA24ON7E1JMKcAq47f7Fufr/wA3bBm4sGXgXsA7dbtS+dJKacAEyimp31ngOYAimJ4X7IvhNcAV5xc
v3coKPEA7W3DKI8sj0AAN0/B4YVEicQACUzF1KVDL3QAlfdu+HggWCwAE11glZo+TzMAhNqwiBfenk4A9JawvEagbJgA0uDWiIwLAgMAAQABo4IB7TCAggHp
MBAGCaC+gAQBgjcVAQSgcAgAMB2Btg4EFgQAFEhuZOVQBdMAgqoXNzcitW2AqMp1ApUwGQYGABQCBAweCgBTAAB1AGIAQwBBJDALIQcPBMEIhjAiD2a/BTAD
wAAwHwEBAiMEGDAWgBQAci06AjGQQ7kAFAVO4eqnxzFA0SOJNDBaAQQfAgQg0TBPoE2gSzyGSaTQoNWv0KECL3Dgcm9kdWMj0eB2oHYDgHUm0V8wM18yMgWC
3V6I3VIwUDBOHYjdQpndJ934C3QwgQKfgRcgBIGXMIEQlDCBkYYkLgMwEIGDMD/FDQIBFkIzfetkb2NzIBtpAG1hcnljcHMuIGh0bTBABggCMAA0HjIgHQBM
AABlAGcAYQBsACBfAHAAb+AAaQCIYwB5oAFzAHTgAip04ANtYABuIAEuIAIdse9n8oalmOAAVHkaLtPYdGcAIpsLlhHhY5IAmUKWfdJ5DJAAwWVfLiw++MMA
ctFtg/6+P+gACso7v0epo/MAadtjvyI1pZcAXWWEkH2LRlAAVdgMknzSGksAHPM8QotS0LAA/WvjPgcuKZsA5j0bpdS1HXcAlDni6WTJRD0AeHoj8xN9ppAA
dION9MsmAkYAKsKKELukqQUADJvtaPpoLpUAoCo/KmtYSWMAHwlpblqYluQAg/TAj/NGK94A/DvQvTXvbiUAruWvJ+3Q3fMADq+ZKJeYTQ4APQvyCInWH8MA
Mhji8MUtzlsAnrRJOQrGCsIAxq2u5bLZ2xUAiFFFWDgycScAGn+x9Cf43iwAOiBpmLJZiWgAbm+nt3TDQAUABqYBKig+gj8AE01mC8CzTfUA4Y9/HG8VfUUA
p3blQCplo8MAXVJihsMdYzYAl4bf2vP48hYAoZon4c2ll9AA7l1jQeNbB5wAhz4GdwbRBrEAdR8UvmFhtfAA3MYbBL7fQccADiju3mUv7JcA9qFcltgA1qEA
Rr1Z85elCUsASBCZgB/QACkAxbGbpT9Fdx4ANcbSoqKfenoAIvpIlR+r+0cAI4D1nvi/a7cAS5fi63V4GuwA6jeZeRhL/9YAsyNodeav+vwAi+sLgOppO68A
/DDtBEyO398AdW1jkT3RnVYATk+/gFcioXgAETIheu9BCrEAP/uozKRdwaEAiJtXcVZOSEUAwELJm3ZbCoAASGv9eZ/BvW0AbWrJUnMTDXoAUM0xghnIMIIA
GcQCAQEwgZV/j2uPa49rj2uPa49rj2sxEDECEzOAfz5jOkCGv0Fz1+BigD4BYStghkgBZQMEYgKQbKCB1AFIhCwJIAMxDAYKhDYCAcYEkAjXAAsxDvCn9wAI
FTAvhwMEMSIEACC0085uqXDKAJlmwDx6UCrcAJsT5WlvH2TyAKfx4eWCyEv8CAgwaOgDDDFaMIBYoDiANgBNgjYqciA3czAAZuA1IACoRQBkwDhlkABXUAAI
YgBWMAJlAHcAAjIQAVMARABLoSgcgBpxP3OPP29tAiD8egSCAQBvKQAg294c0TzYygBfag2rgBAaPQC6KkXINJK2NgCnIk9WBQwCTwCpYuSMmHQdygA8ugGl
XFigxwARIAfoPiiirADBJZaF0dGEoQBDytV2FgXXNQCAvNgH3Su4tABMwNNAYduLhwAzIYqiqkVyewA5Ny86GNIGoQCwtnT+hBfRZgDPM9CngXrzrwBNn/qq
ZIzFpADulWTRhvAhuwCIVl18x8r8VQCHGtAmmextPABWcVJmxPN2JgBSYETZxKJtLgCsfjbLSncOTwAXCYoHZImA3QB46sh1BIW+ggBgBQ7CVTIQ5QCjyii0
xQy3xwC7TlPor/RhbwAJ/OO77mwiVQAp0G+DstqirgAmZmeo4VSD6QBnJNtGIv/IIQBUJyj9MgmhgkAXLDCCFygmGANAAwExghcYMAEUgcYSBwKgghcFIAHA
AQIBAzEPzCLwbQhZBgslHxABBKCoggFIsBVEgAFAMC8BpAWEWQoDATAxAcwDBCCGYQBZxABDldTBxC61DQBh/Gne/9s3WQD8HeB+DN0izwAE+cQCBmRs7wCJ
EY0YEzIwMiAzMDUyODCgOTMAMS4wNzhaMAQAgAIB9KCB2KTggdUwgdKfNZ81nzUjnzWaNS0wK/EBCxMCJPcBSXJlbGFuIGQgT3BlUwJzIABMaW1pdGVkMQgm
MCTjAh1UaGEAbGVzIFRTUyAARVNOOjNCRDQALTRCODAtNjlAQzMxJTAjAzscAWcFVGltZS1TdABhbXAgU2VydoBpY2WgghF70LsaJ9C7D9O74TsBtPsAgAhE
BdIt+gD2AdEAbbx8jxCPEI8QjxDjihCUDQMTHR8LEAsERkIwkbsyMjA54Bowg3EAkbszMTIxNOQA/38a7wnvCe8Jfxp/Gn8afxoffxp/Gn8afBruwPi9AAUA
A4ICDwAwAIICCgKCAgEAALRHpp5lBzJCAB+86K7bsrzpAJbwWhksGwV7ANg5dbhnaq9qAEqb6Z/OhP5iAHgkq9aLEf+XAA7QA8gPtiiGAFTSI7xYbv14AJjz
z29flZpBACmyoPMZdj9zAL12uV65DDdOAHNfNN4+QIgjADF6RN7cTxezADshEspkyI63AHFfkFWVmiXJAAAOxNziMCYKAGGDT22HdO/OAJ8MT8+HOtG3AG3a
0Xf8trvFAGtCxBMtmJXBADZ6qDYKNT8PAEGZe8Ra0kjtANDNdr3UuKlmAHYOl3siGJDCAHntQWu19YtdAN1AUfEqXkV/AIJzDduOBZ85AHtla6chctWtANrI
ZTMGsjDnANjhMbjIw9YVAHELfZFFp7cgAKY2TXlbJsJLAOhXpEDDLVj1AF+VvbJ5qFtaAK7Tf66emtCNAGQaVuO7BfcvAEHTVXcikqgHAIrLV5PYdxzmAH1a
AVeXFm6sAG1SZmcz0BEEAHcmvtbxhxOOAEqC5hT2qrYuACHGBjn9z4+DAKp1ebVCqG7CANskxviv7yy3AGfj8SacSsftAJ7rMZFqhCYiAFLfg/a42XNVAB03
+ls6+ZO0ADXDu/S4D+wWAMgyKmI7HzKHAF9PMQw0piaKABcDlu0PoHSXAB/Lqs6Qb4KtAIZwOzdiBHSeAGyMwiHIdnAGAL7fzDskU/+SAIKdlJ36qzdVAF1r
+Bv6maVsAJwi8MphvElYAM40+z2Stg5uAB6ityPHtPZBAFe3EIelLuGbAMc8m25WaEU5AAIDAQABo4IBAEkwggFFMB0GAANVHQ4EFgQUAMtEheXxlLg6AJy7
Eii3Tt44QMwy2X4wH4EHIwAEGDAWgBSfpwAVXQBeYl2D9ADl0mWnG1M1GRDpcjBfAQgfBFgAMFYwVKBSoFAAhk5odHRwOi8AL3d3dy5taWMAcm9zb2Z0LmMA
b20vcGtpb3CAcy9jcmwvTQUGACUyMFRpbWUtIFN0YW1wAANQQwJBQAEyMDEwKDEEKS6ACjBsBggrAAYBBQUHAQEEIGAwXjBcxQMwAoSGUN4aZXJ0c2cbCHQw
DIEzEwEB/0AEAjAAMBZBAyURQQMMMArFHQMIMAoOwQUPwQUEAwIHAIAwDQYJKoZIQIb3DQEBC4LbAQAAEtEPBYwptwCCYqEqtI6BswDCphfpKg0ftgAbqpgA
rdlnrQDbert7pCkRJQC4oRWpLZdqNQDxx0UkXGc4XgAvXadm0sabsgBCdOSr4hDCSAA7p1dKrwAa2gD3Zmjc895q0gBp5QS7jTIJOABHwquQkweoGwCHqkUW
XtfTrQBVKYMM0LdlDgCIg0qz79vivQB4MuXRVpOJ6QDEDkvFIZHjAABaXaIuVhoEawBOr3f/f9mLEAD31sKJHtLElABt1XrQ5kJGHQBItBYYM9efKgC9eB+a
ruo2pwDqfTSmsQRrtQC3uGb/1/qj6AD+Xpp75KsuRwAjRfr0ONV0vABVbjSsegm/dAAPkuA2lz3HxQB/qIHEr+JXbQBl1upgEVVajQBAKZeVUeNMGADhcXwS
madR1ADqLXDf7CqdhAA4z0k9ivzo7wBY/JAZC9zugwDapYyk66GU3wBgDssh1yY+vgC9u1FSD/6ivAC+h0R2Xf5NhAAvsW1nDM1xFABdFF/VgpkOxAByH6r4
12pm8ACgyhP6+0ZO2gCgoruhhSk0bADNRf6QaYv5zwBm1U0sZM1orwAWt6kscbC9GwCn9PYM/8AQSQA4Ga9Ms845PwD3taCGSoJoDAAAVpyvg3uaYgB7gpfw
HHEpBgDJvxz7vRsVJwCUephsfgb2rwDkCOzG9lnDpwCQmkI0vPRckwAS/UwlQn1ktAC7IgqbKjpN2gAsnbBO/osrewC69I0vQB/LKQASpWWEVylA1wDOg/Cv
dS2xNQBTMIIHcTCCBQBZoAMCAQICEwAzAAAAFcXna+CeAptJmWABoAGsRoAwgYgxCzAJIEsABAYTAlVTMRMEMBGBAQgTCldhAHNoaW5ndG9uBDEQYk8EBxMH
UgBlZG1vbmQxHkQwHCECChMVxlwgAENvcnBvcmF0ImkgBjIwMOEDAxNiKecDUm9vgARgY2kAZmljYXRlIEEAdXRob3JpdHkCIIFhMB4XDTIxADA5MzAxODIy
gDI1WhcNMzDDAXIzwQEwfD8VPxUuFSa0MCQjFR3nA8d1IIB1UaMTggIiaScBDdzkAOGmTOe0ciELAHmiy9ckeb0OANWC0/3unAcHANKpbE51yMo1AFf2AX9s
SuDiAL25PhdgM/9cAE/HZveVU3FaAOJ+Slr+uDZnAIVGIwy1jRPPAHcywBAY6GB9AGpSg0S3po5GAGsHFPPFdvWGAFDcwUTIcVxRADE3oAo4bo3tANcP2CZT
fDlhAAJ6xKr9cmmvAB2rrPY2vjUmAGTamDu6GnszAK2AW36MEBydAFL+tuhiJdxqAA/PXfT+jlPPANbshVZN7928AI2k45GPsjksAFGc6XBpDco2AC1wjjHI
NSi9AOO0hyTD4MmPAH61VI/c+gVVAJhtaDuaRr3tAKSueik3rMvrAINF50ZuyjLVAMCGMFxPLOJiALLNueKNiOSWAKwBSru+cakXAFtnYN74kpEeAB09/SDP
c31BAJpGdc3EXzTdABKJ1v2lIH1+APzZnkXftnIvANt9X4C626p+ADbsNkz2K26oABJR6L8FA6PRAHOmTTd0lBw0AIIP8BDyt0cYAO2n6Jl8P0zbAK9ewvPV
2HM9AENOwTM5TI4CALxCaC4Q6oRRAEbi0b1qGFphAAFzymeiXtcoAHYC4jMYctenACDwwvoSCtdjAG8MyTZki1ugAKaDIV1fMHSRAJSU2LlQ+QuJAGHzNgY1
GIRHANvcG9H9stQcAMVr9lxSUV0SANsluq9QBXpsAMURHXLvjflSAMSFF5PAPBXbABo3xwgVGD94AKtFtvUeh17aAI+eFnJpxq57gLe3PmriLq0FboLdAG7Z
MBIGCXBbAAQBgjcVAQQFKbIBMCM3AQKhbyqnAFL+ZMSavoKRADxGNSnPEP8vXATumHGPb4BvXOEBIAAEVTBTMFEGDAHkBEyDfQEBMEGEMD/FYgIBFjNPagFL
akRvY3MvUmUAcG9zaXRvcnnALmh0bTATkmdsZwIZZgsUAgQMHgoAAFMAdQBiAEMwAEEwCxJp4WgBhsQwD0ZsBTADYABafADV9lbLj+iiXABiaNE9lJBb10DO
mhjEMFZTfE8AME0wS6BJoEc8hkVECxB4TwsifHBy8G9kdWPTdfBE0ERARAJfATotMDYtMjMFwntayHtOMEwwSn3Iez5/ESkGlXu/BbIFdAFPdwEAnVV9/CoA
reEsH2cBMSQAW+Geckv8qW8A6lwUtj5OR2QAeLEGk5c9MTMAtTnXwnE2P9oAZGx80HU5bbsADzHkwo/7bNEAoZQYIu7pZmcAOlNN3Zi6th4AeNg2LpypglYA
AAOwBb6J6GkA4LoJ7nvfam8AvinLbtg/SHUAAdkY3m2CDPUAbSNU5HhTdSQAV7ndn/OOPcYA82jfZfakVqoA95W2KFUn0CQAvUCgvxm2EhIAEV09J+BAljgA
rPf5KYnDvBcAsFSFQrP8DJ4AixmJ5/ALaoEAwoEZQhlSdYoANsIdw2FzLiwAa3tuPywJeBQA6ZGyqVvfSaMAdAy87JGA0j0A5ko+ZjtPu4YA+jIa2Zb0j/YA
kQH2zsZ0/fYATHJvEKt1MMUANLB62FD+ClgA3UA8x1RtnWMAdEgssU5HLcEAFARxv2T5JL4Ac23Kjgm9swEAV0lUZNlz138AHltEAY5aGZEAaw2fpCjcZxkA
KCS6OEuabvsAIVRrakURR6kA8beuyOiJXk8AndLQTHa1V1QACbFpAUR+fKEAYWxz/gq77EEAZj1p/cvBQUkAfn6Tvsv4O+QAtxW/tM4+pTEAUYS8vwLBgqIA
excdFYmNcP4A57XQKBqJC48ANtq6TPmb/woA6TT4JDVnK+AADbjmjJnW4SIA6vAnQj0llOYAdHRbatGePu0AfqAxM328y+kAe784cETRkPEAyKs6ijoIYn8A
2XBjU02N7oIAbaUFEMFxBmoAELQdVTNYs6GAcGbyoYIC12BgBEACQDiCAQChgYDYpIHVMIHS72qP72rvau9q6motMCvxAQgLEyT3AUlyZWyAYW5kIE9wZVMC
AHMgTGltaXRlAmTVbQsTHVRoYQBsZXMgVFNTIABFU046M0JENAAtNEI4MC02ObBDMzEl0ElScBxfcAFQcFNlcnZpY2UIoiMKMA4HBgUrAA4DAhoDFQBlAJzY
kPObl/ZzAHgpEm3+AeQnAB4JCKCBgzCB+ICkfv96DxAPEA8Q/3oH/3r/eok6BQUAAgUAAOgdW7gwIhgCD6C3MzA1MjgxQDI0ODU2WgYBOYEEATB3MD0GCiJP
gIRZCgQBMS/wP04KBATgPrAAAQDAlTJOAjBOoFawABHdAwIeFK04AQI26AMCMSgMMCYAvhYBAwKgCgQwCGEDAwehIKERtQABhqAsCwOBgQAAc6kSzsuQ4QAC
blqJAP4qhwAUQ9vA9mk8dAAcSwcATw4TIwD+ne2CHRQ1bAAGaJ49SmCdmwDDi8VRymWO7QDhGEs2TW5HQgCSIpqpNqIQFgCOu7v6baZ3mgB7oqGiwoH/kgDp
ZwvnSzILHwD6/AbXIqGk5ADd+3xUcu/16AADkpEK/D3ZKwAMSdC/VLLj3ABdMYIEDTCCBHIJoS2Bkx8dHx0VHaazAAcTB1JlZG1vAG5kMR4wHAYDAFUEChMV
TWljAHJvc29mdCBDAG9ycG9yYXRpQG9uMSYwJAF8AwQTHQd8VGltZS0AU3RhbXAgUEMAQSAyMDEwAhMAMwAAAbT7gAiARAXSLfoAAQEaADANBglghkgBAGUD
BAIBBQCgAIIBSjAaBgkqAIZIhvcNAQkDEDENBgsFDBABBAQwLwcbBDEiBCAArI9dsRPUnegAu7CStlktGWcAhj0+eIjFEQAAfENPddsde/cIMIH6CEACLzGB
AOowgecwgeQwAIG9BCDTyPd7AOajMHAGUXG9APr/rElreFPRAOLse71ysdp4ALcB9wYwgZgwAIGApH4wfDELBDAJAXIGEwJVUxAxEzARAQYIEwoAV2FzaGlu
Z3RxAIMQMA4BCmWcAH5jAMV7BGW4yJ2gAD3ogVmcIXYUAGxk/i6ylWb6gGMRn66Uzx4BrgGEfQELBQAEggIAAJjXvuyvnYUAf73yR7AsGykATmgQ/p+Q26EA
e5AlMz2vrm4AZKsucivagkYAaLfvJpHpUcsA6yhMUELaQcsA44NRgceNMTcARkxjTxVM3KAAZDTVHOu/6+QAuL77hho/6xAACsLZmQdWvfsAju9VpkD5hH8A
N1v8jf1lDgsALbiFFb0uYxEARmcK+3seyLIAsy1nxOKNO/QA1524Z9BcVmYAD8sRmGUfKnoAe8lP9jKEPZAAvgaD9fq+TQoACrbIsc/i8NIAjCg+xn1f4ycA
25Pe4mXSAfwAAy99ZcfOnDwA6d3Iuy9NbqIAe9CkFZj1WxUAlnMl2zy+CVcAEVFeVs/YR3UABteWMsO6Uk4Apv8qFh8ejIcA43aLLq298PgA6k5rW+jTqzMA
fJa30UE6hyAAGKndJjgUaTUAnW7QmB8iLgwA6LJf+oHLcUUAeBHHMV3FXKYA10tfd+9+H34AcIbWx4chOxoAkiEcrLID5AwAF3Kn6XFe9VsA2PykIEheqXcA
ZvWU7KbNR7gAaF93JB7gleUASdRt4PWhE38ASMV9BQvhhJUABMzdXLeK5uIAB/KNDeSP/TgAKIyeUXtBxUUA8OmvIXGutzsA0P77laZSGqIAHvBtSuX5uQ0A
+aqoZlkTAKQAljEKQpVt40sA0Nu3L8tGG9EAF/2fJJsoj5YAq1FOOiV2W4kAk6GLz6r+VxMA/FJEreCjItAAiTd7SRWnxRMAU40oElcno9gA2GIVCqpi4bgA
0KEQCzC1e74ACAA=
    )'
    if !DllCall("Crypt32\CryptStringToBinary", "Str", base64, "UInt", 0, "UInt", 1,
        "Ptr", cData := Buffer(80111), "UInt*", cData.Size, "Ptr", 0, "Ptr", 0, "UInt")
        throw Error("Failed to convert b64 to binary")
    if (r := DllCall("ntdll\RtlDecompressBuffer", "UShort", 0x102, "Ptr", data := Buffer(115672),
        "UInt", data.Size, "Ptr", cData, "UInt", cData.Ptr, "UInt*", &cbFinal := 0, "UInt"))
        throw Error("Error calling RtlDecompressBuffer", , Format("0x{:08x}", r))
    return data
}
;
; WebView2Loader.dll (64-bit)
;
; Copyright (C) Microsoft Corporation. All rights reserved.
;
; Redistribution and use in source and binary forms, with or without
; modification, are permitted provided that the following conditions are
; met:
;
;    * Redistributions of source code must retain the above copyright
; notice, this list of conditions and the following disclaimer.
;    * Redistributions in binary form must reproduce the above
; copyright notice, this list of conditions and the following disclaimer
; in the documentation and/or other materials provided with the
; distribution.
;    * The name of Microsoft Corporation, or the names of its contributors 
; may not be used to endorse or promote products derived from this
; software without specific prior written permission.
;
; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
; A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
; OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
; SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
; LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
; DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
; THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
; OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;

WebView2Loader64() {
    base64 := '
    (
CbsATVp4AAEAAAC2BAAwCQBADHgRAHgADAAOH7oOALQJzQAhuAFMzSFUaABpcyBwcm9ncgBhbSBjYW5ubwB0IGJlIHJ1bgAgaW4gRE9TIABtb2RlLiQAAABQ
RQAAZIYLABANdHJkBU/wACKAIAsCDgAASACRUvwDE3BGAAQQAgqAwwGnAgsCAAAFAQQAABkFBwDgAAcAxLrzAuAAAwBgQQU0BQYPD0EDCtHxAQDugAO/EPIB
ACgBCsACAISIBQGAAgDEFIADIEoCAOgngAPQAgAA1AYAAPTpASQAVJCFgOaDH8BhGAEAQAJUAwCg9QEEALgATUjwAQBgQZAbLnRleHSAA+0eRgAaAUiBfQzG
IAAAAGAucmRhdGEAqACMsgAIYIARtIADJkwINIPZQC4DEwAUdh4BHAA8DIEMhJGHE8CcLnADFIJxwDoAFsABAgzOCUAuMDBjZtBnAAA4AQRgwAeBCJIi0Aln
eIEJAJDBMCpwwAcSwAEk0AlyZUB0cGxuZYwBBJBNxBM2ywnDRWxzwQEJCwJRxAk4zzFfUkRBqlRAe1yBQrDECTrRHbhzcmPAAsJ2wHgAwHLkADzSJ2xvAArB
esF81AAIwAFCzglCoMc/AAM/AB4AVkiD7EBIAIsFHBACAEgxAOBIiUQkOEiLAEEIDxBA8A8pAEQkIEiDeSAAAHVmSInOTI1JACBIiVEoTIlBIDBIjRVXgVWN
TAAkIEmJ8P8VtAAaAgCFwHQjDwC38IHOAAAHgACFwA9O8EiLTAHACTHh6NWrAAAAifBIg8RAXsMATItGCEiLTiAgRQ+3CLohK/8Vgn6gBzH269C5oTMEzSmC
EkyLnCSAAcABTYXbdC9MiwBUJHCD+gF1KwBBD7bAjXABhATAuOGWD0XGQYkAA02JSxBNiVMAGEmLQyhIhcAEdRMDDYXSde1BBMcDwRzr5EiLdAAkeE2LWzBM
iYBcJDBIiXQkABkAVCQg/xUBTwIgAOvNVleADlhIgInQRIuUJJCBa4XgD5hhHIsV/w6BIwTiSOAFUA+2MMEA5hhIjVQkQIkAMg+3cAGJcgQASItwA0iJcggA
SI1wC0iLeQgISYk7wQAPtz9BQIl7CEHHQwJrSQCJcxAPt0ALQSiJQxhgAhwhVsdECCQ8qgAASI0FkgTXAeApNUvYAQAEKcbAEzxIi0kgCYEVKETjFGkZAgCU
icZBKlBBKoKqRCoAWF9ew8NWV1MD4BfgM9ZIY8FIjQgNFMugCYs8wUggifnoQGmgGInDAEiNUCpIifHoFmvgieA3IiAEQbgqEyEcgAIeIeIASIn6CEmJ2IAK
IFtfXmzp6YAC4iI4wD9ABqcJQAbooiEFjRXTyIsADAAHkwMH6Gki4QAAwf8VKuQBAINQ+P90cKECU6ICxtpI4Bww4TDgACiBOuAAJiABMyAGuiHgnkG4Ageg
AUUxyf8VGhbjAAsBCA3CCfviASAAsAHrJGAaIMxJYRo9uQAM/9egC/8sFbZAAQADdeAS/9eUMcDgFjiAIUFWoyHCKKEhic+6BCAtgRFUch/jAKxCFsNBAbMB
QgH5SInCQYnYiP8VhmAPicNBABYFYAOFYANMOfB1PAj/FWbgAoP4enWsMbphtIEDJmQJYGcJGmdrCTpiCYBXHonfhcEDNsEDOfh2D8MsBOg4wDAxwOsV/wQV
CCEFwQ+3wQ2hAmfJD07BIBkoIDDaQYcZSIMZQHVxoElEdVpAZhuW4L0ECyFEE9cL4TxDE8BBAYP4A3IANQ+3QwJmg/gAOnUbZoN7BFwAdSQPtwOD4N8Ig8C/
UAEacxXpAs1wGGaDO1x1CqEAAVwPhL1RGrgxKgVzKlwgQYlDEA8ogAWhxgEADymALxDZ6KodsAzJSIlA2uiA/v//oD+IRsXSQcIC2ehB4AdJMUEV2ehCQglw
CsJNEInw6KhSC9noLAFSAcFmulwA6BImULAAIASEk/Ihw0yIjXQkcDDx6AdBAgApw0iDwwJI0Tr7EQH1kw7ABEAr6FttJxD+oAABAiRwCfEPNwD9//8x24TA
ddJR0CIRyWIkcoAlYiRs6K5iBLAmZyABAAImIQAC/9e7AsAY6yCJcTMNssAu/xVA4AGA6wW7BUAAgIJPiOjFHOFBTCRA8Tis8qbwOKEzSIQbV6EbLlWxG2BF
sBvLsBu1CpW2G1BwBb5wBehtIByoSYnH4ADH4QBe4gAqxuAAzOEAT+AAvTKBoAhNhf8PhCXQAKBNhfYPhNFDSEADzYESELEAAElMx3JqABXATIn4/xUpoIvh
ARLdMAGJxTccTI18ICQwSYlHMRzdxCFAQA8pB0xgQuUbVXAC6pEAf+AThJADg7EkXjDoixABIFhMsAWAQYnoSYnBTEFflMdJQl9fgR4oSJNWseEaJEHH4XO0
A09xGaiNFQ4CQ8GQGk1BGmUACojjAyBIkAVwW9K0dBbRGGJBFYIDZgAJADHt6zT/FebfsaAmt+iBwCmTZegTAoJEEALrFP8Vxv8BKWVSW6VQDehhUltdMXEZ
QV/D4WVwKc6LAAWuJgIAiw3sABQCAGVIixQlQljiXgzKO4ERmH8gI0iLDYQQAkiFFMl0UDvyYVFeSP9MJYDQBsJGIF7BIWmJIALopNA9gz1doABI/3XIQAGU
xzAC0sRBuPGD/xXuEAOBaSoVkAHAmgHUkQGJBaIdYQaNDR6hBMGgBBjrhMwDAFMkU0iBROzgwgkFcwgUJISEJNjScckPhFgAIBZM8CUoHrQybEmJRgmgZkYY
wRhJiQ5JAIlWCE2JRhBISzAa4FlGESDbwlE8BkgPKUbwfkbgMADQJQEiQHEg0xmhGHwksfAr+ejGwQDwGb5wACWwNUxgNmITkh24R8gBALkBw+iWkDSxK0Vh
J8oAAQ8QhHIIDxAQjCSgcQApjCRiwHIAhCSwcACwCQyLYXDgbyNwCEmJBiAXBAklIxcNSIsBSICLQAj/FV9H0RFIBdDBIgIPKMMDD4IowwRBDxFGEEAAgk6Q
iF4wSIsDQQOxgCr/FSdwAyAGOCEGA60IEjwPKUkQDylAAUyJ8uh8UTLDJEmLEAhAEPAN/xVE6UZwgS27A+A+67ZA7wPiAwERBOEDPeIDbfERsNAW8RKocQBQ
AkBk6J6RAIuM8hohKcjyopJCgcQhHcJCQCnmQoiB7OgSErQk0MI80yBKkUN7BnYfyCxZkDBISIlBwBw1DhASD1ApMegaEgcLURQdQGaDOQB0F/FBMADor/n/
/4nFQQK+ARFFMf/rG4sgSxhFMfbCAUUxMsDwd+gioC8gArcBAInuhe11LkiLmnPAmlsgI/E2hBoRCQ580DpwiSA0wbIBRSiJ8ElQD8nBQ8aFAPZ5SIXtD5TD
kIsFYyOhNZERrzWJ0Q2PQjFLiw01UAIVUQoSYCTZsEj/FSPK3KMyNBMHYhezEzIPSbATjKFRjw8o1BGBTsTBEpY9IDQTD6Ck0hHADOgh9aFoeLeDBD3+8JsD
ciL2BaIKwAFAdBngFASQAARIueW8SCHBSDkowXQnEAnzsALHBUbJUAASTMcF3qQA/wQV4DAD6WX///+oSI1EMDHHUQEBYQoQV0SIOTEUVogagkygAVBBiTBM
YAEKYJBVcZApKTFJiUBBUEnHQVjBxEkwiUlAuAEYQAFISQSJUaBYQThNiUEKIAACKMERTIlMJC4oAZIxVBANQdGnjRVYg80BMBsyGlCQDemiUIIIDfshIEMm
cG4Igz3voAD/D4WlkyB4gAFww3lGbNtyRlbFIAKwAcZBA1lAA+m2uyB4/v//zAgAQVcAQVZBVFZXVVMASIHsAAEAAA8AKbQk8AAAAEgAiwX4AwIASDFA4EiJ
hCToAUSFENIPhPEBEInXSQS8qgQATI20JMgBAChNiWYYD1fAAEEPEUYIQcdGghgAJABJiQ5IADwCsAAUTIlmEA8oEDVdvgEAYTYPKRR28AAD4AAD0EyNCLwk
gAIh+ehSFSEAXY2cJJgCZdnoQkIBD4nx6DoAB0wAifFMifro3g4BASJMJGBMiWEQIA8pMegeAjNMJCpABRANBBAgBRD8FAEAiosOSIXJdBgAZoM5AHQSSI0A
VCRg6JH2//8AhcB0K4nF60Qwi4wk4AE6AQxMjSZEgCaBIOgEgIjrIYC9A0AAgOnMgg8RgDzobReDFEBIiQDB6AT4//+JxUGAIwQxwOttAjzoAkQAEITAdTpI
jQAVV8EBAEyNdCEBT/HoVhaAY418EQFN+egbABJJicQNAQUcAAWAD0iJwk2wieDoYoISBBn1AAboSYnHAQX2AAWAOIGCgvEABTHtSIkHgzcmLIBwgoHoIoQE
YOgWGIEEgBoQggPZ6AhFggyMwlro+xNBeIwBw3Ux4eglngAAkInoDyjEfoHEgYIAW11fXkFcQV6oQV/DgolVBorYAAkFAYrAwm1MJFhMiVDHSYnUQAJUwI3A
CgHGjbgBCig1ZrwBA0FgSIsdOtgBEABFMe1BL1QkSAS+BEAIKe6DfCQAVAEPRfVIjQUECsPACos88Ei4AYWYSIlEJHAPKRuAD0FBLoAugYLy6Pgo8v//QQTe
QonBMQDSSYn4TYnh6MTHBkFfD4XLwBbBB1K+wweyAcQHp8QHqwvAB0ExkIAgiwWyHgACAIsN0AwCAEBlSIsUJVjCwAwIyjuBQSgPj44DkcADgz2DQAkAQYE1
EAAPhNAASYsFiVUCDpcVDqMDDloBDg90hJ2ADEwARkFhgEo1S0AFBWVIgE84RMA6MIpMAAEoQQIgMclAewBFMcBFMcn/FQBIQAIAMdKFwIB4VkiJlCSgQxCu
A0EQQHJDEFSADNLAC0ZMwBQBCP8VEwANTGSLpMIH/9OCSWBMTACLZCRI/xXm1jABADHAATXBA4sFpM4dQRnMC1QZLEEZiIsFoKAESIXA4B/hoALHhCSMwADh
NEABhogBIwAAuQEAGAAbDpQCAuQRwQT/FYM/AAIAg/h6D4WTicABg7wjBg+EhUEN/Sg+hKKGoTPiHGCC4gDgWFwuESAVAwvBAcPAQYSAwHQ5TIslCOESTUAC
zkACChBJiQYQTKFmH/o+AgCgdjEhBsTsEAEbHZ/VQE8ARgLdwAGD/QSNRQEAQQ+TxYnFg/gABQ+FUv3//+l2poA4AQZrQAyAFyEKAAR0KaB4SYPELjFA20mL
TCTq4XMdRFcAgQsj/8MAA1BkO5wiBXLgQT3hGOgGeyAM4hDriEEPt3QEJGA9UGAeIVHgAUTUJP6AAZSFAfyAASGiFYIB+oABnGEai1QkatpCCExAWh2AIoYL
HgehGYABoQlMieLoEkoFgbf/ABy+1MCvhCa24ALgX4Su4ACIRBAkR7oPYin56EGPAQeKMEEEhTBBuAuBRDhMJFBBtiECIB1BuVIKQQ7JVOIdCgIS6S64gMzg
CQEhhEAKQbyX4EbJB8YGksIGdcmABYFApXy/AQDoMyEZBWMHKEABQf/MdcWtogqKIBWhFluAC+milACNDf4aAgDoGRFgoYM98kAB/w+FRFn8QA+NDVFACf+w
FbfTAQF/QAsl6AGsBcBABWAEwYEHRIAHzOkkgwbhAujLgIUAVqiDPbEDCkFjAwACCEpmBgoO6AEFfwMKgKXhB/PjB+kJ4wZ8YQKid2ACgz1wAwq7AwOiryDh
/xUVBgrS6AFUBT4DCj+BB6KAB+kWhoEGYCdYgdgSifCNAAbiQFyAdMLoIcA3BUO+JWDjMfZB9sWiAUHcDYa7QQp6QArgvgIAB4ChhAGX8V7yNfAkifDxXiFc
8F4RXQ30Xl0SX/SBVldTSMiD7FBQP+r78AZRXRBEJEhNsB5jv1dDQQXwCF5IidPAgXQAVkyJxg8oBXkGtoAC0HEwDykCD3IpQEzoY8AF0gKAOjEVoQEgMTRN
Yih0IDEAwItMhCA5TIQAMHcrcjBI/8BASIP4BHXr0HQolr+Bd3EPSEELgJdACwT4SAA1W19ew7hBkFQA6wW4/wAAiWAGMf/r10FqAmqDAOw4SInWSInPBWAL
M2cLMEiNXCQIKEjH0SgAQLUBgEUx/0Ux9kDgEkB1CkLHBL5hAetCP7EoidpBuAIq+YEgUEKJBL5IixBZIEg5+HQUgE90DwBmgzgudQlIgwDAAkiJx+sMMUDt
TYX/dQXxARWASYP/A0mNR5FDBsZwe7IMnEGA5gEFYQwwYQy5lgAARDEgHIPEOBIX2BbMzCBJickxySJc6fGI8f//Jg2B7GigR4hMic6QdonTSaINxFj6pA2E
JGDBAQB2EFBBuAhyAvGyqojoMDvgWUQkPEGMA2g9oRlIiQIPtsMISMfBwAKASCnBhZNj28NmQbkZAqAq6BUABRJSIoEjAQbBC/T8lTAY2AAj4QjmC7MNhWCT
PHEWKEyJdCAeUI0Vf7TgZdvla7kgBAIAicWiAv8VQpTAAIXtdaSAfzwoA3KdQQlQ0YpUDAVTiwphnonBZrpcEADo8D3xS8B0RoBIicNIg8MCMCbeFZAFEpgw
JrEkAUBBsCSSJGBOdAsTHOgJoQQNQZFIsILgBACJw+lCMcAiMdvpKmAAVhpXcCIocCIAcI0VxAC6AQBEiwQQRIA5BAF3DHIYsB1iBLAbEHXq0AigGiigX17p
4eqSO6mgApBIiz0i0H//17EKxF4Nsgr/FRcgAQAC8tYAMP/XYAViA7cdAQAM6b3AGPgAi0EMPQHACH90DI1QAfAAD7FRDHXs6wVSuiEBidCgA1ZACiChRgJC
jXD/QAJxQAKQhfZ1OcJASIugJUxAIEAJ4XUkOOGADVS1FaCC9vEBFPMBEIj/FQmgAesFvpASGn/SJyChCVIQWEiJEs7wJAj4pjJQhdJoeDNIwCMoQTHhPmzM
SYuABeANFUHxD0CshWAewRCV/xWwN4AdAMJMiwfrSotGADiFwH7G/8iJAEY4DxBGEA8QRk6AIBAfDylJsLgBBaEYAnAthcB5T0gAi04wSIsRTIsQShiJwjGC
icj/5BVksATrNNAA0wGhC7AY/xVOUAGBIygRDVYWdgmmDS70AVAhKllbkIXCF1jAF1MeiXAazpmwpX6x4VVAA0kwkQQgFUjHRjCKBOU2oAIAx0YMsBTAkCQ6
CNEdxpIoARPBHA8LCfEEScdSjkSLGkQAi1IERItKCIsAUgxFhdt1FkWAhdJ1EUGB+WFVEHUIgfpgAEZ0KAS4AnBMQYH7iTMAik51LEGB+tggydJLdSNwAra1
ABJPdRqB+u5sgMFNdRJJiQijCPAI/xVaoAgzJBEkc1gTcDuBGl/2hhooiwV0KRRBmxcgO0+bQJv/IfEAgz36EwA7dEKEuoOyfvHoVQhzABaPcE7RHCCwxIsd
1RtQAlEBi1EBYTTCSIkg2P8VzjWRQA+EioJSoshAAosNplC+aw8HAAfcg6maoQSAI0o5IspIx/Ep8Z+gBInHGUCsU0gQjIBg8ehgg6AI0NIU/xXuy/CJYLf4
gc8AwGIAB06C+FEdIP8VlQBgIQAhv5AEB4DrGilxA//KkQPkkAMxyQCEwL///wCAD0xF+TMiMCBVkaRiMEuhYjA5BNAI6O+AOoMoPfgScnjoQYqNDbSlt0Fy
jYAHoC12wABjkjzyAIkFxqACMALHyWAA6BpwIOmzQwNxAdToodIEutMEC/A5gAHCs1BpMf8x0hDCoAnX8CRxBEAQE8AFr7ABwgWCMMIFx0iJPXbzBcp34QS6
4ATpxPAFEV+HwR5QOWIriwVv9Ic5qxBr4lXGsB8BsAMvIQsIjRX4MEdJifBJA1Cc0aFIg8cYTI0gRghEiHTmWA1oAaACX7sASI0VQ7cBAEkAifnodAAAAEgA
jXwkSEyJN0gEuKoEAEiNXCQwAEiJQxAPKAWvAK4BAA8pA0iJENnouAUAsIPGGABEiHQkKEiJdMAkIEiNDX0AkgCg0kQCoPhJAEwgAaYADgKbAVyLTCRQSDEA
4ejIjwAAkEgAg8RYW19eQV4Aw0FXQVZWV1UAU0iD7DhMic8ATInGSInTQIoIrCSYATyLBYHzAQBVMeBIiUQkMABAhO10B8YFZQD9AQABTIu0JAKQAl/66EEI
AAAghMB0OkgAx98HAQETBk2F9g+EAIIBAAuFwA+EsQIoQMEx0kG4CgAK6AAwUQAAMcmD+MABD5TB6ZaACIAsIHUNgD0LgCwADxSEyIAITICFKEnHk4AmgAWJ
fIFwFS2BcATHwYARgEUxwEEAuRkAAgD/FecBABqJxUmLD/8VAswABYXtdExIx0hEJCiJHPO2ghwCDYscrYIcgYwo/xWQAYIdD5QFh/wBAAB1SOsOMclBiUAO
6z/GBXUACAEGTIKyAyFIidpJiQrwgdo5gDGEwHUa14UOAU2HDhsCoUyA4IC7RFCOg7s4W10BvEESXwK9QVQCX4HsoAnACg8pw1RMic5MAInHSYnWSInLiYBg
/vGEYIQkiEAHDEm8RYfBSFBNiWcBQIc1kawBAEEPSCk3TMAdmQPBEPmA6FX7//9IjcAfAEyJYRAPKTHotoABBgANcAENRQtrAAUIMclMwXHk//+FCMB4OMEM
cOgVBgECbWa6XADo+zUpQnJ1CoMG+sKfwAIBAhdIicLoKwQAxADrAgcw6MfAAoMJLiNAFoZiQoQDAEhmQTSDPgB5+AR5yCLx6KQTTMEOUCrBJR1BD6CNFTi1
AQIzqIAVQcABTIny6J2DAugOc4EhQBqAwEwkIDE+7cC6ACMCeMAZAHjM+xUAeMOBCpjAbYXbD2SFhIJknCSCpoAOUCzoLgTHABFcwHCJwpECz/HomoGltQFA
d6pEwzUFFApxw4AeyAaQjRXYtETh8ejAumVHmSpAJOsCgCqCFALLoBKjEPjhEYuMAjyhRUQijIAG6A8ohGyBlsThQyJHXGZHVlehdopQpnZJwEaLvCQhBQmg
RsjvBndITYX/AHRwSI1EJETH40ExYg5AxwHAKCA8QjgPgDQhNSGGQCvxMdJJIInYQbkQoih++rEgY8B0WOACZ1t7oh4AdFZIiw5IhcmEdGtme1RNAAAge5Tr
LiEeSGEZVotiCgtmB4BgUIKPQV/pNCFABoN8JEQggcAPALbAQYkHQLYBlQAk9qYHGKAHifBoBiDDMcDr1OUfgexOUGAoSSBAH83uBmZIQ6EDoExAQbgIAgX5
IDHS6KUvQSBEJPA8xwAE4S5hmyGFUSAzgAZAIHv5AUkAYBhIUI1UJEABnTgiB/kk6O5hOIkGgEuUw6chOCEO4RZgiuAW2CA3AwEURRfMzMxIicgAD1fADxEB
SMfiQeErAMNWoDiAh0FWCQA3QRAAbXQdSIlEzmaBNUiLSQACyTB0DOjb4E8iB0YISaAhIF7kBonOywnoXgmiOiEmYATnRCAAK0gAOVEIc3NIiddASIP6/3RH
wYuJkPhI/8CAIT8CwJcC/wAASA9JyOhnk2FdwBAkScAqiwMiEgBMi3sQTI0ERSchIuAjAYbMicB+DjHA9usfZkHHwIVBBBVhTQhBbitgCEyJc2AQSIl7CMMR
piBWDlcAEmBlAJzPSIXSSHQNSOBkF0hgm4kYwOsDAHgAK0iJ8mFgBihfXumhGqUYKLsHowsmBaIlYRzgDycigUD66P7+//+AVBaoSItLQRc/gYcYYBZgSDl7
CHPgFsISKIED4UiJO0iLQ2IJoOhmxwR4IBvgcgwBoDxBCEg50HIS6EiJEcUzBkAGAH3AApAPk8DD8hs3R/kbE3saMANATREtz0iLgBlMAcNyMElAGzFBA9ro
KUMN8EYPSAAByUgDTxBNAYL20BhNifDoO/BDwEg5XwhzEMQNNhdASIkfSItHYgzmBbAKWOAN3sxIiwEgTDnAdglRDGZCCIkUQdAAD5fAwwBI0epI/8Lpv4j9
//8wAkEIw5ECYMNIgzkAYDrxDxAHMRzSCsAPSI09qagBEDcPRflIjRxVQfEhSDnTdiFAGP+YFWH2kAFABxNI4QzGwVAZYDXok4fwB1E+T0YKMBPzBEITMdJA
Ev8MFVQAdbADOInDiTrCIRQuAAmgD5AV8egGdrEqERHCQYnY/5wVKaACQgL0BOlWYBLTgBbUBczM0nZV9HaCJCjORIlgEddhU408CBJMiTJwy/z//9iIRCQQ
JBIuEFAEESUAVUj/zzHtTI0AJQmvAQBFD7YALC6E20mJ70wQD0X/T4Il6EjBQOgEQg++FBAM8YToo2ADTo0EfeEjAEGD5Q9DD75UIiVQOfHoiQEF/8WASIPH
/3K3ioEGWxEog11do131mGAiCsUSQXWA9ukWXVj/FYYgAA+BFUZIiccAZ4aC0KHwFf8VYMByAYgPhMSSK4wkuPE6BXAAsNReIESJ8YkC6qBY/xWEKQIAEInG
6R9gCv8V/wK/8KW38IHOAAAEB4AABE7wTI10oCRUQYk2+ah80WJSR/GoH6TxqAcxUCiNgIa60WRwQUGwAfFhIo1xDo0N9GAJTIskNYtACUH/cAz56I6+MByA
CtEAjQ1r0BQ1cgHZ8wCx4AJ0Aub60P//6aPSV2WfCZ8JaZiyhaOWso5QBJoJ2YTo8wEIjQ1+rZIJpvGwBRMI6CSZCSeVCFjZ6FwwBBAWGRIW+VD/Ff6+kxcJ
0gBYa9EAwGpYQV9r8IUiLWAZU57DuBEgkDPsKOiil4Ax6wIzISko8Cgg6d9CAADwYOl/e3ABcQDrAC1wAAkA0YQIIbFEILqgDzFrDToR4Lj/FdQxB40Nzaon
wQBfAgjY4ZkVQAGUAChBAUpGAXR/sAsCC0ABSIvL/xVCCZIDFRvzAEiL+P/EFS/iDP90FcEC0FpIPf7ygQ4F/2AA6wAeRTPJRTPAMwDJQY1RAf8V8xq8ogGs
EQLhYTPJ6FbAYJowORmgB43ADugO7JKMwBiSDiBfw7lJMbzoXdBgzEAjPouK2cACcDAE/xXCAAUAgzsAdRGDC/9Q6zS5ZKECnkAA6wDqgzv/dO9lSAiLBCWw
SgCLDcQJ8AJBuCKLixTIi4gFwObwAIkEEKAEBiXhCIE+SP8l8b0qAXsGCHIGWnAGiwUWjDADIAH1ALWLFXMhgQHAiQV3QAGJAwmWBkG54iKLBNCLRAVcoAFD
iQSAD5qbYAUiBukhCvUFBdORBKLZ4nFEi8GAFZqxuhiNDYNhABQJHyYCRSEBgCAB/xVScQSLDA1rwABgFYvT/xXKKLMcYRgDrbswDBJkWIsFeXEB8AUSMAIt
JTMCKCACyiVABYsNqiNCBX1DBRbnATNREKPwIzEEjQ0FUgJHUAUZUALw8AEFEGv/FR0nEQHRKPYS6w9QIejZTizAsiFbsABNQJOA5wPCCZAs+/90BuhDccB+
zOhdUQCyLcApAABI99gbwPfY/0bIAy40BYM91gAH/2GwBXUH6CTgniEG0wVACcBgAeiHMwAAADPShcBID0TTGEiLwjMGcgsYTIsQwbhNWuDCOQXVAMT//3V4
SGMNFAjFkjjF8ABIA8oAgTlQRQAAdV8EuAsQNGY5QRh1AFRMK8IPt1EUAEiDwhhIA9EPALdBBkiNDIBMAI0MykiJFCRJADvRdBiLSgxMADvBcgqLQggDIMFM
O8By0JTCKBDr3zPSUHd1BDIAwOsUg3okAH1BkQAKsAHrBnAAAmoysSwYczw78CwAESEFEiMw8ihICOsFSAA7yHQUM8DwSJAPsQ3UsLd17kIDNCjDMAT3sBjz
EIrZDOj7UBMxD3QLhDa8ANt1B0iHFabvAAEASIPEIFvDAEBTSIPsIA+2BAWbAJCFybsBAAAAAA9Ew4gFiwEAPOgOBQAA6AEAJAAAhMB1BDJAwOsU6LAqAhgJ
EDPJ6BEALuvqiiLDA5DMzMwDloA9Ak8AdACK2XQEhCDSdQzokgBiisuA6OMjAACwAQ5WAiQBK4vZdWeD+QABd2roUQYAAACFwHQohdt1JJBIjQ0OAYStMQET
VHUQAA8WAQ+dAg90Ai4AjzNmD28F6QIjAczI//MPfwXE3e4AC4kF5gAGAQ6LAQcADu8ABsYFuQAFigEFgrmAbADoOgA+AMzMSIlcJAhIAIlsJBBIiXQkBBhX
    )'
    base64 .= '
    (
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
    )'
    base64 .= '
    (
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
    )'
    base64 .= '
    (
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
    )'
    base64 .= '
    (
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
    )'
    base64 .= '
    (
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
    )'
    base64 .= '
    (
+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
    )'
    base64 .= '
    (
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
    )'
    base64 .= '
    (
+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
ZHQAdK10AIR0AAUAmPQAqnwBBZB+dhB6UmVnaXMD0MH1AFNldEluZjBvcm1hkcNVAVVuAnJ8AldyaXRlVKByYW5zZkIBAIAEgENsb3NlS2UwMgPRAKDTVmFs
dWVXIdQBT3BlbsABRXiDAQHwAFF1ZXJ5EgIBIwEAQ29UYXNrAE1lbUFsbG9jARoBRnJlZQBBREBWQVBJMzIhcwDYb2xllAAJAPlADmEOqwE3MQAMgFIcMAAs
MABXf3d2MnUzNGACSzAAaS0wAJIwAFEcAhCmQ28AbXBhcmVCcm/CdzDfVmVyc1HVtJDoQ29yZYkyCJHfAdkBA8jZMeZBdmFpbGEMYmzqAusGU3RyafxuZ6Jf
BQChXGFfDwC0X1UBAGZ0AHZ0AIR0AJxVdACsdADEdADSdADepXQA8nQAAvlzAA50AKoYdAAmdAA0dABIdACqYnQAcHQAenQAhnQAqph0AKp0ALx0ANJ0AErm
dAD8dAAS+nMALFV0AEZ0AFx0AGp0AHpVdACQdACmdAC6dAA7uVDG+gEAAQDYBHDqpQQ4/AQ4DPsDHB4EHKouBBxIBBxUBA5gBA6qbgQOegQOogQOuAQOStAE
DuQEDgD8AwcSVQQHIgQHOgQHTAQHXlUEB24EB4QEB5oEB7BVBAfKBAfcBAfqBAf+qQQHGP0DBywEBziEA6pGhANahANmhAN6hAOqioQDmoQDuIQDzIQDqtiE
A+KEA/CEA/6EA6wa/oQ7hAM8hANUhAOaaoQDeoQDBQBY+IRHVYQDdoQDhIQDnIQDrFWEA8SEA9KEA96EA/KphAMC+YMDDoQDGMQBqibEATTEAUjEAWLEAapw
xAF6xAGGxAGYxAGqqsQBvMQB0sQB5sQBqvzEARLElSzEAUbEAapcxAFqxAF6xAGQxAH6psQBusQB/63/rf+t/60P/63/Vv9W71aUAENsAG9zZUhhbmRsAGUA
zgBDcmVhAHRlRXZlbnRXCAAA2uQBRmlsZQBXACMBRGVsZQB0ZUNyaXRpYwBhbFNlY3RpbwBuAEUBRW5jbwBkZVBvaW50ZThyAEngAeAAzQQAeAABRXhpdFBy
bwBjZXNzAI8BRkhpbmSiDwCVYgFGkGlyc3RBDUV4YA8ipmICTmV4QgJXAAC0AUZsc0FsbCBvYwAAtWEBRnIQZWUAtiEBR2V0gFZhbHVlALehAYpTpQG5oAF1
    )'
    base64 .= '
    (
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
    )'
    base64 .= '
    (
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
HwAfAO8fAB8AHwACAIAvAQ8ADwD/DwAPAA8ADwAPAA8ADwAPAP8PAA8ADwAPAA8ADwAPAA8A/w8ADwAPAA8ADwAPAA8ADwBBDwByYQAAbjAAe1UwAGkwAKQw
AJQwAHdVMABlMADKMAC3MADAVTAAqTAAoDAAkDAAcwUwAGEwAPtiAAD0VTAA7TAA5jAA3zAA1VUwAMswAMEwALcwALtVQIK0MACtMACmMACfVTAAlTAAizAA
gTAAd0EwAKNkAACcMACVVTAAjjAAhzAAgDAAeTUwAHIwAGswAAEAvryrMApAnfhwAC9wAKowAFqPMACAgZ4wAJ0wAGVVMABWMADgMAJzcABAVTAAGDAAwPAA
hgCgf1UwAHEwAGMwAFUwAEFVMAAtMAAZMAAFMAC2UMAAAK8wAKEwAJNVMACFMABxMABdMABJVTAANTAAEoB7CzAA/VDBAADvMADhMADT1TAAxTAAtzAAqTAA
DwD/DwAPAA8ADwAPAA8ADwAPAF0NAAFyWDCG/EABEAAApAAwfwEACcBeSJAAYGDAAgAogWEMACgEBTRQAFYAUwBfEVAARQBSkABJAE/UAE7wAElQAEawAAEA
ML0E7/7xBDEAIABcHwd1APWoMWUCvAWIBUABAfAEdAByAGkQAG4AZ9AEaQBsBABlkAVuAGYAb0UwAmQyAjAANDAAOa1yAGJxDPBrFnABQzACqm2wmGHwAnnQ
CGHQACplsgVNkARjcAVvAKpzMABmMAYg0gJy0AI1UQBhEAFpkADxzYYAVi+wBLUHRDAAc7IDaY+wAlcCPwUxBUUAZHALqmWSAG2wCWXwAGRSAKggAEKyAnfQ
AmWQAKggAFdwAGJQFGlwAGp38ABM0AFh0gJTozhUAAx4CFZyAXP4BzEUAC6wDy5wADgAMo0Qfi4wAPHDRgATcAPVMRN0MgNuUAVs2BB7B2oyegcucABsEAAB
AJDUADZwBExwAWcSBPESRnBwFZEQZwBo0AUAXz8BcAx/Eb8WUwwukAFBdfIGIBgEc9IAURcRCXbr0hNx4k5yDU+UAhEiUQlf9RHRAP8N/w33DX5yHlDRkgpk
AHUwC3Q/I/8dz/8d/x3/Hf8dADzyHfsHR10ePx4zHjwACv4uUwHQE3m8AG8AcgB0AE4AAGEAbQBlAAAAIE0AaQBjAJhvAApzABhmANgAAIYAIC8AAQBQAlRk
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
    )'
    base64 .= '
    (
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
    )'
    if !DllCall("Crypt32\CryptStringToBinary", "Str", base64, "UInt", 0, "UInt", 1,
        "Ptr", cData := Buffer(103116), "UInt*", cData.Size, "Ptr", 0, "Ptr", 0, "UInt")
        throw Error("Failed to convert b64 to binary")
    if (r := DllCall("ntdll\RtlDecompressBuffer", "UShort", 0x102, "Ptr", data := Buffer(160232),
        "UInt", data.Size, "Ptr", cData, "UInt", cData.Ptr, "UInt*", &cbFinal := 0, "UInt"))
        throw Error("Error calling RtlDecompressBuffer", , Format("0x{:08x}", r))
    return data
}

class WebViewGui extends Gui {
    /**
     * Creates a new Gui with a WebViewCtrl and necessary custom handling attached.
     * @param Options AlwaysOnTop Border Caption Disabled -DPIScale LastFound
     * MaximizeBox MinimizeBox MinSize600x600 MaxSize800x800 Resize
     * OwnDialogs '+Owner' OtherGui.hwnd +Parent
     * SysMenu Theme ToolWindow
     * @param Title The window title. If omitted, it defaults to the current value of A_ScriptName.
     * @param EventObj OnEvent, OnNotify and OnCommand can be used to register methods of EventObj to be called when an event is raised
     * @param {Object} WebViewSettings May contain a CreatedEnvironment, DataDir, EdgeRuntime, Options, or DllPath
     * @returns {WebViewGui}
     */
    __New(Options?, Title?, EventObj?, WebViewSettings := {}) {
        super.__New(Options?, Title?, EventObj?)
        DefaultWidth := WebViewSettings.HasProp("DefaultWidth") ? WebViewSettings.DefaultWidth : 640
        DefaultHeight := WebViewSettings.HasProp("DefaultHeight") ? WebViewSettings.DefaultHeight : 480
        /** @type {WebViewCtrl} */
        this.Control := WebViewCtrl(this, "w" DefaultWidth " h" DefaultHeight " vWebViewCtrl", WebViewSettings?)
        this.Control.IsNonClientRegionSupportEnabled := True
        this.Control.wv.AddHostObjectToScript("gui", {
            __Call: ((Hwnd, Th, Name, Q) => GuiFromHwnd(Hwnd).%Name%(Q*)).Bind(this.Hwnd)
        })
        this.Sizers := WebViewSizer("-Caption +Resize +Parent" this.Hwnd)
        this.OnEvent("Size", this.Size)
        for Prop in this.Control.OwnProps() {
            if (!this.HasProp(Prop)) {
                this.DefineProp(Prop, this.Control.GetOwnPropDesc(Prop))
            }
        }
        DllCall("Dwmapi.dll\DwmSetWindowAttribute", "Ptr", this.Hwnd, "UInt", DWMWA_WINDOW_CORNER_PREFERENCE := 33, "Ptr*", pvAttribute := 2, "UInt", 4)
        this.Move(,, DefaultWidth, DefaultHeight) ;Sets an initial size that is somewhat reasonable
        this.Control.wvc.Fill() ;Fill the window after setting initial size
        WebViewSizer.ToggleSizer(this) ;Toggle Sizers
        return this
    }

    LastMinMax := ""
    Size(MinMax, Width, Height) {
        ; Resize the WebView2 to fit the GUI
        this.Control.Move(0, 0, Width, Height)

        ;Resize the sizing handles to fit the GUI
        this.Sizers.Move(0, 0, Width, Height)

        if (MinMax == this.LastMinMax) {
            return
        }
        this.LastMinMax := MinMax

        ; When not visible, WebView2 stops rendering reducing its CPU load. When
        ; added to a hidden window, like we do in this class, the WebView2 is
        ; created non-visible by default and must be made visible before it will
        ; appear. This handler satisfies both situations.
        this.control.wvc.IsVisible := MinMax != -1

        if (MinMax == 1) { ; -1, 0, 1
            try this.Control.ExecuteScriptAsync("document.body.classList.add('ahk-maximized')")
            this.Sizers.Hide() ;Always hide the Sizers if the window is maximized
        } else {
            try this.Control.ExecuteScriptAsync("document.body.classList.remove('ahk-maximized')")
            WebViewSizer.ToggleSizer(this) ;Check if Sizers should be displayed or not
        }
    }

    __Delete() {
        ; Placeholder
    }

    ;-------------------------------------------------------------------------------------------
    ;Default GUI Overrides
    /** @throws {Error} Not applicable for a WebViewGui. */
    NotApplicableError(Msg := "") {
        throw Error("Not applicable for a WebViewGui. " Msg, -2)
    }

    /** @throws {Error} Not applicable for a WebViewGui. */
    Add(ControlType := "", Options := "", Value := "") => this.NotApplicableError("Did you mean AddRoute()?")

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddActiveX(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddButton(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddCheckbox(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddComboBox(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddCustom(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddDateTime(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddDropDownList(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddDDL(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddEdit(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddGroupBox(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddHotkey(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddLink(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddListBox(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddListView(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddMonthCal(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddPicture(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddPic(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddProgress(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddRadio(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddSlider(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddStatusBar(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddTab(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddTab2(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddTab3(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddText(Options := "", Value := "") => this.NotApplicableError("Did you mean AddTextRoute()?")

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddTreeView(Options := "", Value := "") => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    AddUpDown(Options := "", Value := "") => this.NotApplicableError()

    /** Close WebView2 instance and delete the window. */
    Destroy() {
        this.Sizers.Destroy()
        this.Sizers := 0
        Super.Destroy()
    }

    /** @throws {Error} Not applicable for a WebViewGui. */
    SetFont(Options := "", FontName := "") => this.NotApplicableError()

    /**
     * Display window. It can also minimize, maximize or move the window.
     * @param Options (Optional Parameter) Positioning: Xn Yn Wn Hn  Center xCenter yCenter AutoSize
     * Minimize Maximize Restore NoActivate NA Hide
     */
    Show(Options := "") {
        if (!((Style := WinGetStyle(this.Hwnd)) & 0x00800000)) {
            this.GetClientPos(&gX, &gY, &gWidth, &gHeight)
            Width := RegExMatch(Options, "w\s*\K\d+", &Match) ? Match[] : gWidth
            Height := RegExMatch(Options, "h\s*\K\d+", &Match) ? Match[] : gHeight

            Rect := Buffer(16, 0)
            DllCall("AdjustWindowRectEx",
                "Ptr", Rect,    ; LPRECT lpRect
                "UInt", Style,  ; DWORD dwStyle
                "UInt", 0,      ; BOOL bMenu
                "UInt", 0,      ; DWORD dwExStyle
                "UInt"          ; BOOL
            )
            Options .= " w" Width += (NumGet(Rect, 0, "Int") - NumGet(Rect, 8, "Int"))
            Options .= " h" Height += (NumGet(Rect, 4, "Int") - NumGet(Rect, 12, "Int"))
        }

        Super.Show(Options)
    }

    /** @throws {Error} Not applicable for a WebViewGui. */
    Submit(Hide := true) => this.NotApplicableError()

    /** @throws {Error} Not applicable for a WebViewGui. */
    FocusedCtrl {
        get => this.NotApplicableError()
    }

    /** @throws {Error} Not applicable for a WebViewGui. */
    MarginX {
        get => this.NotApplicableError()
        set => this.NotApplicableError()
    }

    /** @throws {Error} Not applicable for a WebViewGui. */
    MarginY {
        get => this.NotApplicableError()
        set => this.NotApplicableError()
    }
}

class WebViewSizer extends Gui {
    /**
     * Helper class for adding sizing handles to a caption-free WebViewGui
     */
    static __New() {
        OnMessage(0x0024, (Params*) => WebViewSizer.WM_GETMINMAXINFO(Params*))
        OnMessage(0x0083, (Params*) => WebViewSizer.WM_NCCALCSIZE(Params*))
        OnMessage(0x00A1, (Params*) => WebViewSizer.WM_NCLBUTTONDOWN(Params*))
        OnMessage(0x007D, (Params*) => WebViewSizer.WM_STYLECHANGED(Params*))
    }

    /** Tests if the cursor intersects with the sizing handles */
    static HitTest(lParam, Hwnd, &X?, &Y?) {
        static BorderSize := 29
        X := lParam << 48 >> 48, Y := lParam << 32 >> 48
        WinGetPos &gX, &gY, &gW, &gH, Hwnd
        Hit := (X < gX + BorderSize && 1) + (X >= gX + gW - BorderSize && 2)
            + (Y < gY + BorderSize && 3) + (Y >= gy + gH - BorderSize && 6)
        return Hit ? Hit + 9 : ""
    }

    /**
     * Ensures the borderless window does not turn into a borderless
     * fullscreen window
     */
    static WM_GETMINMAXINFO(wParam, lParam, Msg, Hwnd) {
        if (!((CurrGui := GuiFromHwnd(Hwnd)) is WebViewGui) || (WinGetStyle(Hwnd) & 0x00800000)) {
            return
        }

        if (ParentHwnd := DllCall("GetParent", "Int", CurrGui.Hwnd)) {
            ;If window has a parent, use it's parent's size
            WinGetPos(,, &ParentWidth, &ParentHeight, ParentHwnd)
            MaximizedXPos := 0, MaximizedYPos := 0, MaximizedWidth := ParentWidth, MaximizedHeight := ParentHeight
        } else {
            ;If window does not have a parent, use it's monitor's size
            MonitorInfo := Buffer(40), NumPut("UInt", MonitorInfo.Size, MonitorInfo)
            hMonitor := DllCall("MonitorFromWindow", "UInt", Hwnd, "UInt", Mode := 2)
            DllCall("GetMonitorInfo", "Ptr", hMonitor, "Ptr", MonitorInfo)
            MonitorLeft := NumGet(MonitorInfo, 4, "Int"), MonitorTop := NumGet(MonitorInfo, 8, "Int")
            MonitorRight := NumGet(MonitorInfo, 12, "Int"), MonitorBottom := NumGet(MonitorInfo, 16, "Int")
            MonitorWorkLeft := NumGet(MonitorInfo, 20, "Int"), MonitorWorkTop := NumGet(MonitorInfo, 24, "Int")
            MonitorWorkRight := NumGet(MonitorInfo, 28, "Int"), MonitorWorkBottom := NumGet(MonitorInfo, 32, "Int")
            MaximizedWidth := MonitorWorkRight - MonitorLeft, MaximizedHeight := MonitorWorkBottom - MonitorTop
            MaximizedXPos := MonitorWorkLeft - MonitorLeft, MaximizedYPos := MonitorWorkTop - MonitorTop
        }

        NumPut(
            "Int", MaximizedWidth,  ; Maximized Width
            "Int", MaximizedHeight, ; Maximized Height
            "Int", MaximizedXPos,   ; Maximized xPos
            "Int", MaximizedYPos,   ; Maximized yPos
            lParam, 8
        )
        return
    }

    /** Redirects sizing area clicks to sizer's associated parent GUI */
    static WM_NCLBUTTONDOWN(wParam, lParam, Msg, Hwnd) {
        if (!(GuiFromHwnd(Hwnd) is WebViewSizer)) {
            return
        }

        if (Hit := this.HitTest(lParam, Parent := DllCall("GetParent", "Ptr", Hwnd, "Ptr"), &X, &Y)) {
            Buf := Buffer(4), NumPut("Short", X, "Short", Y, Buf)
            PostMessage(0x00A1, Hit, Buf, Parent)
            return 0
        }
    }

    /** Hides or shows sizers in sync with parent GUI style */
    static WM_STYLECHANGED(wParam, lParam, Msg, Hwnd) {
        if (!((CurrGui := GuiFromHwnd(Hwnd)) is WebViewGui)) {
            return
        }

        WebViewSizer.ToggleSizer(CurrGui)
    }

    /**
     * Checks the Parent GUI for WM_SIZEBOX and WM_BORDER styles
     * and toggles the Parent's Sizers' visibility as needed.
     *
     * @param Parent Parent GUI of a intialized Sizer
     */
    static ToggleSizer(Parent) {
        if (!(Parent is WebViewGui)) {
            return
        }

        if (((Style := WinGetStyle(Parent)) & 0x00040000) && !(Style & 0x00800000)) {
            Parent.Sizers.Show()
        } else {
            Parent.Sizers.Hide()
        }
    }

    /**
     * When a GUI has -Caption and +Resize, it normally shows a wonky looking
     * default sizing border. This handler recalculates the window size to
     * render the client area over top of where that sizing border would
     * normally be, so that it is hidden.
     */
    static WM_NCCALCSIZE(wParam, lParam, Msg, Hwnd) {
        if (!((CurrGui := GuiFromHwnd(Hwnd)) is WebViewGui) || (WinGetStyle(Hwnd) & 0x00800000)) {
            return
        }

        return 0
    }

    __New(p*) {
        super.__New(p*)
    }

    __Delete() {
        ; Placeholder
    }

    Move(X, Y, Width, Height) {
        ; Adjust the sizing handles to fit the GUI, first punching a big hole
        ; in the center for click-through, then resizing it to fit the GUI.
        hRgn1 := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", Width, "Int", Height, "Ptr")
        hRgn2 := DllCall("CreateRectRgn", "Int", 6, "Int", 6, "Int", Width - 6, "Int", Height - 6, "Ptr")
        DllCall("CombineRgn", "Ptr", hRgn1, "Ptr", hRgn1, "Ptr", hRgn2, "Int", RGN_DIFF := 4)
        DllCall("SetWindowRgn", "Ptr", this.Hwnd, "Ptr", hRgn1, "Int", true)

        DllCall("SetWindowPos",
            "Ptr", this.Hwnd, "Ptr", 0,
            "Int", 0, "Int", 0, "Int", Width, "Int", Height,
            "UInt", 0x4210 ; SWP_ASYNCWINDOWPOS | SWP_NOACTIVATE | SWP_NOOWNERZORDER
        )
    }
}

class WebViewCtrl extends Gui.Custom {
    /**
     * Creates a WebControl instance around a Gui.Custom control
     * @param Target The Gui you want to attach the control to
     * @param {String} Options Control options such as width, height, vName
     * @param {Object} WebViewSettings May contain a CreatedEnvironment, DataDir, EdgeRuntime, Options, or DllPath
     * @returns {WebViewCtrl}
     */
    static Call(Target, Options := "", WebViewSettings := {}) {
        Container := Gui.Prototype.AddCustom.Call(Target, "ClassStatic " Options)
        for Prop in this.Prototype.OwnProps() {
            Container.DefineProp(Prop, this.Prototype.GetOwnPropDesc(Prop))
        }
        Container.__Init(), Container.__New(WebViewSettings?)
        return Container
    }

    static __New() {
        OnExit((*) => WebViewCtrl.CloseAllWebViewCtrls())
    }

    static Template := {}
    static Template.Framework := "
    (
        <!DOCTYPE html>
        <html>
            <head>
                <meta http-equiv="X-UA-Compatible" content="IE=edge">
                <style>{2}</style>
            </head>

            <body>
                <div class="main">{1}</div>
                <script>{3}</script>
            </body>
        </html>
    )"

    static Template.Css := "html, body {width: 100%; height: 100%;margin: 0; padding: 0;font-family: sans-serif;} body {display: flex;flex-direction: column;} .main {flex-grow: 1;overflow: hidden;}"
    static Template.Name := "Template.html"
    static Template.Html := "<div style='padding:100px;'>The documentation for <b>WebViewToo</b> is currently being reworked. Sorry for the inconvenience.</div>"
    static Template.JavaScript := ""

    static UniqueId => WebViewCtrl.CreateUniqueID()
    static CreateUniqueId() {
        SplitPath(A_ScriptName,,,, &OutNameNoExt)
        Loop Parse, OutNameNoExt {
            Id .= Mod(A_Index, 3) ? Format("{:X}", Ord(A_LoopField)) : "-" Format("{:X}", Ord(A_LoopField))
        }
        return RTrim(StrLower(Id), "-")
    }
    static TempDir := A_Temp "\" WebViewCtrl.UniqueId

    static ActiveHwnds := Map()

    __New(WebViewSettings?) {
        DllPath := WebViewSettings.HasProp("DllPath") ? WebViewSettings.DllPath : "WebView2Loader.dll"
        DataDir := WebViewSettings.HasProp("DataDir") ? WebViewSettings.DataDir : ""
        Options := WebViewSettings.HasProp("Options") ? WebViewSettings.Options : 0
        EdgeRuntime := WebViewSettings.HasProp("EdgeRuntime") ? WebViewSettings.EdgeRuntime : ""
        CreatedEnvironment := WebViewSettings.HasProp("CreatedEnvironment") ? WebViewSettings.CreatedEnvironment : 0
        Html := WebViewSettings.HasProp("Html") ? WebViewSettings.Html : WebViewCtrl.Template.Html
        Css := WebViewSettings.HasProp("Css") ? WebViewSettings.Css : WebViewCtrl.Template.Css
        JavaScript := WebViewSettings.HasProp("JavaScript") ? WebViewSettings.JavaScript : WebViewCtrl.Template.JavaScript
        Url := WebViewSettings.HasProp("Url") ? WebViewSettings.Url : ""

        this.wvc := WebView2.Create(this.Hwnd,, CreatedEnvironment, DataDir, EdgeRuntime, Options, DllPath)
        this.wv := this.wvc.CoreWebView2
        WebViewCtrl.ActiveHwnds[this.Hwnd] := this.wvc
        this.wv.InjectAhkComponent().await()
        this.wvc.IsVisible := 1
        if (A_IsCompiled) {
            this.BrowseExe()
        } else {
            this.BrowseFolder(A_WorkingDir)
        }

        this.wv.add_NavigationStarting(InstallGlobal)
        InstallGlobal(ICoreWebView2, Args) {
            static Proxy := { __Get: (this, Name, *) => %Name% }
            Host := WebViewCtrl.ParseUri(Args.Uri).Host
            if (Host ~= "i)\.localhost$" || this._AllowGlobalHosts.Has(Host)) {
                try ICoreWebView2.AddHostObjectToScript("global", Proxy)
            } else {
                try ICoreWebView2.RemoveHostObjectFromScript("global")
            }
        }

        ; Add the request router
        this.wv.add_WebResourceRequested (p*) => this._Router(p*)
        if (Url) {
            this.Navigate(Url)
        } else {
            this.NavigateToString(Format(WebViewCtrl.Template.Framework, Html, Css, JavaScript))
        }
        return this
    }

    ;This never seems to be called
    __Delete() {
        ; Placeholder
    }

    ;-------------------------------------------------------------------------------------------
    ;Custom Uri Routing

    _DefaultHost := "ahk.localhost"

    /**
     * Adds folder access into the WebView2 environment under the given host
     * name. Host names provided here should end with `.localhost` for best
     * performance.
     *
     * Folders added by this method cannot easily be used in compiled scripts.
     *
     * @param Path The path to the folder to add
     * @param Host The host name to add the folder under, e.g. `ahk.localhost`
     *
     */
    BrowseFolder(Path, Host := this._DefaultHost) {
        this.wv.SetVirtualHostNameToFolderMapping(Host, NormalizePath(Path), WebView2.HOST_RESOURCE_ACCESS_KIND.ALLOW)

        NormalizePath(Path) {
            cc := DllCall("GetFullPathName", "str", Path, "uint", 0, "ptr", 0, "ptr", 0, "uint")
            buf := Buffer(cc * 2)
            DllCall("GetFullPathName", "str", path, "uint", cc, "ptr", buf, "ptr", 0)
            return StrGet(buf)
        }
    }

    /**
     * Adds exe resource access into the WebView2 environment under the given
     * host name.
     *
     * @param {String} Path Path to the exe to load resources from
     * @param {String} Host Host to make the resources available on
     */
    BrowseExe(Path?, Host := this._DefaultHost) {
        if (IsSet(Path)) {
            throw Error("Not yet supported")
        }

        this._CompileRoutesForHost(Host, [['**', (Uri) => WebViewCtrl.ExeRead(Uri.Path)]])
    }

    /**
     * Adds access to an individual file.
     *
     * @param {String} FilePath The path to load the file from
     * @param {String} Route    The route to make the file available under, if
     *                          different than the name of filePath.
     * @param {String} Host     The host name to add the file under
     */
    AddFileRoute(FilePath, Route?, Host := this._DefaultHost) {
        SplitPath(FilePath, &Name)
        if (A_IsCompiled) {
            this.AddRoute(Route ?? Name, (Uri) => WebViewCtrl.ExeRead(FilePath))
        } else {
            this.AddRoute(Route ?? Name, (Uri) => FileRead(FilePath, "RAW"))
        }
    }

    /**
     * Adds a text resource at the specified route
     *
     * @param {String} Route The route to make the resource available under
     * @param {String} Text  The text content for the resource
     * @param {String} Host  The host name to add the file under
     */
    AddTextRoute(Route, Text, Host := this._DefaultHost) {
        this.AddRoute(Route, Text, Host)
    }

    /**
     * Adds a resource at the specified route
     *
     * @param {String} Route    The route to make the resource available under
     * @param          Resource The resource to make available
     * @param {String} Host     The host name to add the resource under
     */
    AddRoute(Route, Resource, Host := this._DefaultHost) {
        this._Routes[Host].Dirty := true
        this._Routes[Host].InsertAt(1, [Route, Resource])
        if (!this._Routes.Dirty) {
            this._Routes.Dirty := true
            SetTimer(() => this._SaveUnsavedRoutes(), -1)
        }
    }

    /**
     * Allow pages at the given host to access the `ahk.global` object.
     * @param Host The host name to allow access under
     */
    AllowGlobalAccessFor(Host := this._DefaultHost) {
        this._AllowGlobalHosts[Host] := true
        ; TODO: Make change on any active page
    }

    /**
     * Shows a specified resource in the web view
     *
     * @param Path The path to the resource, not including any leading slash
     */
    Navigate(Path) {
        this._SaveUnsavedRoutes()
        if (!(Path ~= "i)^[^\/\\:]+:")) {
            Path := "https://" this._DefaultHost "/" LTrim(Path, "/\")
        }
        this.wv.Navigate(Path)
    }

    /** List of hosts allowed to access names in AHK's global scope */
    _AllowGlobalHosts := Map()

    /** Map of hosts to route lists */
    _Routes := WebViewCtrl._RouteMap()
    class _RouteMap extends Map {
        Dirty := false ; Has not been compiled since last change
        __Item[Name] => (
            this.Has(Name) || this.Set(Name, WebViewCtrl._RouteList()),
            this.Get(Name)
        )
    }

    /**
     * Contains a list of route objects. Route objects are a two-element array
     * pairing a route string and a resource.
     */
    class _RouteList extends Array {
        Dirty := false ; Has not been compiled since last change
    }

    /** Map of hosts to compiled regular expressions */
    _CompiledRoutes := Map()

    /**
     * Compiles any routes that have been changed since the last time they
     * were compiled
     */
    _SaveUnsavedRoutes() {
        if (!this._Routes.Dirty) {
            return
        }

        this._Routes.Dirty := false
        for Host, RouteList in this._Routes {
            if (!RouteList.Dirty) {
                continue
            }
            RouteList.Dirty := false
            this._CompileRoutesForHost(Host, RouteList)
        }
    }

    /** Compiles the routes for a specified host */
    _CompileRoutesForHost(Host, Routes) {
        ; Clear any overriding folder mappings that would prevent custom routing
        try this.wv.ClearVirtualHostNameToFolderMapping(Host)

        FullReg := ""
        for Route in Routes {
            Pattern := "^[\/\\]{0,}(\Q" StrReplace(Route[1], "\E", "\E\\E\Q") "\E)$(?C" A_Index ":Callout)"
            Pattern := StrReplace(Pattern, "**", "\E.{0,}?\Q")
            Pattern := StrReplace(Pattern, "*", "\E[^\/\\]{0,}?\Q")
            FullReg .= "|" Pattern
        }

        this._CompiledRoutes[Host] := {Pattern: "S)" SubStr(fullReg, 2), Routes: Routes.Clone()}

        ; Register the router to handle requests made against this domain
        this.wv.AddWebResourceRequestedFilter("http://" Host "/*", 0)
        this.wv.AddWebResourceRequestedFilter("https://" Host "/*", 0)
    }

    /** Connects requests to target resources */
    _Router(ICoreWebView2, Args) {
        Parsed := WebViewCtrl.ParseUri(Args.Request.Uri)
        Path := Parsed.Path, Host := Parsed.host

        Target := unset
        CompiledRoutes := this._CompiledRoutes[Host]
        RegExMatch(Path, CompiledRoutes.Pattern)
        if (!IsSet(Target)) {
            return
        }

        if (Target is Object && !(Target is Buffer)) {
            try Target := Target(Parsed)
        }

        if (Target is Buffer) {
            Stream := WebView2.CreateMemStream(Target)
            Args.Response := ICoreWebView2.Environment.CreateWebResourceResponse(Stream, 200, "OK", "")
            return
        }

        if (Target is String) {
            Headers := ""
            if (Path ~= "i)\.js$") {
                Headers .= "Content-Type: text/javascript;"
            }
            Stream := WebView2.CreateTextStream(Target)
            Args.Response := ICoreWebView2.Environment.CreateWebResourceResponse(Stream, 200, "OK", Headers)
            return
        }

        if (Target is WebView2.Stream) {
            Args.Response := ICoreWebView2.Environment.CreateWebResourceResponse(Target, 200, "OK", "")
            return
        }

        Callout(Match, Num, Pos, Haystack, Needle) {
            Target := CompiledRoutes.Routes[Num][2]
            return -1
        }
    }

    ;-------------------------------------------------------------------------------------------
    ;Static WebViewCtrl Methods
    static CloseAllWebViewCtrls() {
        for Hwnd, WebView in this.ActiveHwnds {
            try WebView.Close()
        }
    }

    static ConvertColor(RGB) => (RGB := RGB ~= "^0x" ? RGB : "0x" RGB, (((RGB & 0xFF) << 16) | (RGB & 0xFF00) | (RGB >> 16 & 0xFF)) << 8 | 0xFF) ;Must be a string

    static CreateFileFromResource(ResourceName, DestinationDir := WebViewCtrl.TempDir) { ;Create a file from an installed resource -- works like a dynamic `FileInstall()`
        if (!A_IsCompiled) {
            return
        }

        ResourceName := StrReplace(ResourceName, "/", "\")
        SplitPath(ResourceName, &OutFileName, &OutDir, &OutExt)
        ResourceType := OutExt = "bmp" || OutExt = "dib" ? 2 : OutExt = "ico" ? 14 : OutExt = "htm" || OutExt = "html" || OutExt = "mht" ? 23 : OutExt = "manifest" ? 24 : 10
        Module := DllCall("GetModuleHandle", "Ptr", 0, "Ptr")
        Resource := DllCall("FindResource", "Ptr", Module, "Str", ResourceName, "UInt", ResourceType, "Ptr")
        ResourceSize := DllCall("SizeofResource", "Ptr", Module, "Ptr", Resource)
        ResourceData := DllCall("LoadResource", "Ptr", Module, "Ptr", Resource, "Ptr")
        ConvertedData := DllCall("LockResource", "Ptr", ResourceData, "Ptr")
        TextData := StrGet(ConvertedData, ResourceSize, "UTF-8")

        if (!DirExist(DestinationDir "\" OutDir)) {
            DirCreate(DestinationDir "\" OutDir)
        }

        if (FileExist(DestinationDir "\" ResourceName)) {
            ExistingFile := FileOpen(DestinationDir "\" ResourceName, "r")
            ExistingFile.RawRead(TempBuffer := Buffer(ResourceSize))
            ExistingFile.Close()
            if (DllCall("ntdll\memcmp", "Ptr", TempBuffer, "Ptr", ConvertedData, "Ptr", ResourceSize)) {
                FileSetAttrib("-R", DestinationDir "\" ResourceName)
                FileDelete(DestinationDir "\" ResourceName)
            }
        }

        if (!FileExist(DestinationDir "\" ResourceName)) {
            TempFile := FileOpen(DestinationDir "\" ResourceName, "w")
            TempFile.RawWrite(ConvertedData, ResourceSize)
            TempFile.Close()
            FileSetAttrib("+HR", DestinationDir "\" OutDir)
            FileSetAttrib("+HR", DestinationDir "\" ResourceName)
        }
    }

    static EscapeHtml(Text) => StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(Text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), "`"", "&quot;"), "'", "&#039;")

    static EscapeJavaScript(Text) => StrReplace(StrReplace(StrReplace(Text, '\', '\\'), '"', '\"'), '`n', '\n')

    static ExeRead(ResourcePath) {
        ResourcePath := StrReplace(StrUpper(LTrim(StrReplace(ResourcePath, "/", "\"), "\")), "%20", " ")
        SplitPath(ResourcePath,,, &OutExt)
        ResourceType := (OutExt = "bmp" || OutExt = "dib") ? 2 : (OutExt = "ico") ? 14 : (OutExt = "htm" || OutExt = "html" || OutExt = "mht") ? 23 : (OutExt = "manifest") ? 24 : 10
        Module := DllCall("GetModuleHandle", "Ptr", 0, "Ptr")
        Resource := DllCall("FindResource", "Ptr", Module, "Str", ResourcePath, "UInt", ResourceType, "Ptr")
        if (!Resource) {
            return
        }
        ResourceSize := DllCall("SizeofResource", "Ptr", Module, "Ptr", Resource)
        ResourceData := DllCall("LoadResource", "Ptr", Module, "Ptr", Resource, "Ptr")
        ConvertedData := DllCall("LockResource", "Ptr", ResourceData, "Ptr")
        return WebView2.CreateMemStream(ConvertedData, ResourceSize)
    }

    static ForEach(Obj, Parent := "Default", Depth := 0) {
        if(!IsObject(Obj) || (Type(Obj) = "ComObject")) {
            return
        }

        Output := ""
        for Key, Value, in Obj.OwnProps() {
            try Output .= "`n" Parent " >> " Key
            try Output .= ": " Value
            try Output .= WebViewCtrl.ForEach(Value, Parent " >> " Key, Depth + 1)
        }
        for Key, Value in base_props(Obj) {
            try Output .= "`n" Parent " >> " Key
            try Output .= ": " Value
            try Output .= WebViewCtrl.ForEach(Value, Parent " >> " Key, Depth + 1)
        }
        return Depth ? Output : Trim(Output, "`n")

        base_props(Obj) {
            iter := Obj.Base.OwnProps(), iter() ;skip `__Class`
            return next

            next(&Key, &Value, *) {
                while (iter(&Key))
                    ; try if !((Value := Obj.%Key%) is Func)
                        return true
                return false
            }
        }
    }

    static FormatHtml(FormatStr, Values*) {
        for Index, Value, in Values {
            Values[Index] := WebViewCtrl.EscapeHtml(Value)
        }
        return Format(FormatStr, Values*)
    }

    static ParseUri(Uri) {
        static Pattern := "^(?:(?<Scheme>\w+):)?(?://(?:(?<UserInfo>[^@]+)@)?(?<Host>[^:/?#]+)(?::(?<Port>\d+))?)?(?<Path>[^?#]*)?(?:\?(?<Query>[^#]*))?(?:#(?<Fragment>.*))?$"
        if (!RegExMatch(String(Uri), Pattern, &Match)) {
            return
        }
        Parsed := {}
        Parsed.Scheme := Match["Scheme"], Parsed.UserInfo := Match["UserInfo"], Parsed.Host := Match["Host"]
        Parsed.Port := Match["Port"], Parsed.Path := Match["Path"], Parsed.Query := Match["Query"]
        Parsed.Fragment := Match["Fragment"], Parsed.Authority := (Parsed.UserInfo != "" ? Parsed.UserInfo "@" : "") . Parsed.Host . (Parsed.Port != "" ? ":" Parsed.Port : "")
        return Parsed
    }

    ;-------------------------------------------------------------------------------------------
    ;WebViewCtrl class assignments
    AddCallbackToScript(CallbackName, Callback) => this.AddHostObjectToScript(CallbackName, Callback.Bind(this)) ;Similar to `AddHostObjectToScript()`, but only registers a callback
    RemoveCallbackFromScript(CallbackName) => this.RemoveHostObjectFromScript(CallbackName) ;Removes a registered callback
    Debug() {
        this.OpenDevToolsWindow()
    }

    Move(Params*) => (Super.Move(Params*), this.wvc.Fill())

    SimplePrintToPdf(FileName := "", Orientation := "Portrait", Timeout := 5000) {
        Loop {
            FileName := FileSelect("S", tFileName := IsSet(FileName) ? FileName : "",, "*.pdf")
            if (FileName = "") {
                return CancelMsg()
            }

            SplitPath(FileName, &OutFileName, &OutDir, &OutExt)
            FileName := OutExt = "" ? FileName ".pdf" : Filename
            if (FileExist(FileName)) {
                Overwrite := OverwriteMsg()
                if (Overwrite = "No") {
                    continue
                } else if (Overwrite = "Cancel") {
                    return CancelMsg()
                }
            }
            break
        }

        Settings := this.Environment.CreatePrintSettings()
        Settings.Orientation := Orientation = "Portrait" ? WebView2.PRINT_ORIENTATION.PORTRAIT : WebView2.PRINT_ORIENTATION.LANDSCAPE
        PrintPromise := this.PrintToPdfAsync(FileName, Settings)
        try PrintPromise.await(Timeout)
        if (!PrintPromise.Result) {
            ErrorMsg()
        } else {
            if (MsgBox("Would you like to open this PDF?", "Print to PDF", "262148") = "Yes") {
                Run(FileName)
            }
        }

        ErrorMsg() => MsgBox("An error occurred while attempting to save the file.`n" FileName, "Print to PDF", "262144")
        CancelMsg() => MsgBox("Print Canceled", "Print to PDF", "262144")
        OverwriteMsg() => MsgBox(OutFileName " already exist.`nWould you like to overwrite it?", "Confirm Save As", "262195")
    }

    ;-------------------------------------------------------------------------------------------
    ;Controller class assignments
    Fill() => this.wvc.Fill()
    CoreWebView2 => this.wvc.CoreWebView2 ;Gets the CoreWebView2 associated with this CoreWebView2Controller

    /**
     * Returns a boolean representing if the WebView2 instance is visible
     */
    IsVisible { ;Boolean => Determines whether to show or hide the WebView
        get => this.wvc.IsVisible
        set => this.wvc.IsVisible := Value
    }
    Bounds { ;Rectangle => Gets or sets the WebView bounds
        /**
         * Returns a Buffer()
         * You can extract the X, Y, Width, and Height using NumGet()
         * X is at offset 0, Y at offset 4, Width at offset 8, Height at offset 12.
        **/
        get => this.wvc.Bounds

        /**
         * Value must be a Buffer(16) that you've inserted values into
         * using NumPut(). See the above notes regarding the appropriate offsets.
        **/
        set => this.wvc.Bounds := Value
    }

    Bounds(X?, Y?, Width?, Height?) { ;Get: Object with X, Y, Width, Height properties; Set:
        tBounds := this.wvc.Bounds
        if (IsSet(X) || IsSet(Y) || IsSet(Width) || IsSet(Height)) {
            IsSet(X) ? NumPut("Int", X, tBounds, 0) : 0
            IsSet(Y) ? NumPut("Int", Y, tBounds, 4) : 0
            IsSet(Width) ? NumPut("Int", Width, tBounds, 8) : 0
            IsSet(Height) ? NumPut("Int", Height, tBounds, 12) : 0
            this.Bounds := tBounds
        } else {
            return Bounds := {
                X: NumGet(tBounds, 0, "Int"),
                Y: NumGet(tBounds, 4, "Int"),
                Width: NumGet(tBounds, 8, "Int"),
                Height: NumGet(tBounds, 12, "Int")
            }
        }
    }
    ZoomFactor { ;Double => Gets or sets the zoom factor for the WebView
        get => this.wvc.ZoomFactor
        set => this.wvc.ZoomFactor := Value
    }
    ParentWindow { ;Integer => Gets the parent window provided by the app or sets the parent window that this WebView is using to render content
        get => this.wvc.ParentWindow ;Returns the `Hwnd` of the Ctrl this instance is attached to
        set => this.wvc.ParentWindow := Value ;Not recommened to use set => because it dettaches the WebView2 window and can break the software
    }
    DefaultBackgroundColor { ;HexColorCode => Gets or sets the WebView default background color.
        get {
            BGRA := Format("{:X}", this.wvc.DefaultBackgroundColor)
            return SubStr(BGRA, 5, 2) SubStr(BGRA, 3, 2) SubStr(BGRA, 1, 2)
        }
        set => this.wvc.DefaultBackgroundColor := WebViewCtrl.ConvertColor(Value)
    }

    /**
     * RasterizationScale, ShouldDetectMonitorScaleChanges, and BoundsMode all work together
     * If you want to use set => (RasterizationScale||ShouldDetectMonitorScaleChanges||BoundsMode)
     * you will need to turn on DPI Awareness for your script by using the following DllCall
     * DllCall("SetThreadDpiAwarenessContext", "ptr", -3, "ptr") ;**NOTE: DpiAwareness Now causes fatal error, good luck**
    **/
    RasterizationScale { ;Double => Gets or sets the WebView rasterization scale
        get => this.wvc.RasterizationScale
        set => this.wvc.RasterizationScale := Value
    }
    ShouldDetectMonitorScaleChanges { ;Boolean => Determines whether the WebView will detect monitor scale changes
        get => this.wvc.ShouldDetectMonitorScaleChanges
        set => this.wvc.ShouldDetectMonitorScaleChanges := Value
    }
    BoundsMode { ;Boolean => Gets or sets the WebView bounds mode
        /**
         * 0: UseRawPixels; Bounds property represents raw pixels. Physical size of Webview is not impacted by RasterizationScale
         * 1: UseRasterizationScale; Bounds property represents logical pixels and the RasterizationScale property is used to get the physical size of the WebView.
        **/
        get => this.wvc.BoundsMode
        set => this.wvc.BoundsMode := Value
    }
    AllowExternalDrop { ;Boolean => Gets or sets the WebView allow external drop property
        get => this.wvc.AllowExternalDrop
        set => this.wvc.AllowExternalDrop := Value
    }
    SetBoundsAndZoomFactor(Bounds, ZoomFactor) => this.wvc.SetBoundsAndZoomFactor(Bounds, ZoomFactor) ;Updates Bounds and ZoomFactor properties at the same time

    /**
     * MoveFocus()
     * 1: Next; Specifies that the focus is moved due to Tab traversal forward
     * 2: Previous; Specifies that the focus is moved due to Tab traversal backward
     * 0: Programmatic; Specifies that the code is setting focus into WebView
    **/
    MoveFocus(Reason) => this.wvc.MoveFocus(Reason) ;Moves focus into WebView

    /**
     * NotifyParentWindowPositionChanged()
     * Notifies the WebView that the parent (or any ancestor) HWND moved
     * Example: Calling this method updates dialog windows such as the DownloadDialog
    **/
    NotifyParentWindowPositionChanged() => this.wvc.NotifyParentWindowPositionChanged()

    ;-------------------------------------------------------------------------------------------
    ;WebView2Core class assignments
    Settings => this.wv.Settings ;Returns Map() of Settings
        AreBrowserAcceleratorKeysEnabled { ;Boolean => Determines whether browser-specific accelerator keys are enabled
            get => this.Settings.AreBrowserAcceleratorKeysEnabled
            set => this.Settings.AreBrowserAcceleratorKeysEnabled := Value
        }
        AreDefaultContextMenusEnabled { ;Boolean => Determines whether the default context menus are shown to the user in WebView
            get => this.Settings.AreDefaultContextMenusEnabled
            set => this.Settings.AreDefaultContextMenusEnabled := Value
        }
        AreDefaultScriptDialogsEnabled { ;Boolean => Determines whether WebView renders the default JavaScript dialog box
            get => this.Settings.AreDefaultScriptDialogsEnabled
            set => this.Settings.AreDefaultScriptDialogsEnabled := Value
        }
        AreDevToolsEnabled { ;Boolean => Determines whether the user is able to use the context menu or keyboard shortcuts to open the DevTools window
            get => this.Settings.AreDevToolsEnabled
            set => this.Settings.AreDevToolsEnabled := Value
        }
        AreHostObjectsAllowed { ;Boolean => Determines whether host objects are accessible from the page in WebView
            get => this.Settings.AreHostObjectsAllowed
            set => this.Settings.AreHostObjectsAllowed := Value
        }
        HiddenPdfToolbarItems { ;Integer => Used to customize the PDF toolbar items
            /**
             * None:         0
             * Save:         1
             * Print:        2
             * SaveAs:       4
             * ZoomIn:       8
             * ZoomOut:      16
             * Rotate:       32
             * FitPage:      64
             * PageLayout:   128
             * Bookmarks:    256 ;This option is broken in the current runtime. See: https://github.com/MicrosoftEdge/WebView2Feedback/issues/2866
             * PageSelector  512
             * Search:       1024
             * FullScreen:   2048
             * MoreSettings: 4096
             * Add up numbers if you want to hide multiple items, Ex: 257 to hide Bookmarks and Save
            **/
            get => this.Settings.HiddenPdfToolbarItems
            set => this.Settings.HiddenPdfToolbarItems := Value
        }
        IsBuiltInErrorPageEnabled { ;Boolean => Determines whether to disable built in error page for navigation failure and render process failure
            get => this.Settings.IsBuiltInErrorPageEnabled
            set => this.Settings.IsBuiltInErrorPageEnabled := Value
        }
        IsGeneralAutofillEnabled { ;Boolean => Determines whether general form information will be saved and autofilled
            get => this.Settings.IsGeneralAutofillEnabled
            set => this.Settings.IsGeneralAutofillEnabled := Value
        }
        IsNonClientRegionSupportEnabled { ;Boolean => The IsNonClientRegionSupportEnabled property enables web pages to use the app-region CSS style
            get => this.wv.Settings.IsNonClientRegionSupportEnabled
            set => this.wv.Settings.IsNonClientRegionSupportEnabled := Value
        }
        IsPasswordAutosaveEnabled { ;Boolean => Determines whether password information will be autosaved
            get => this.Settings.IsPasswordAutosaveEnabled
            set => this.Settings.IsPasswordAutosaveEnabled := Value
        }
        IsPinchZoomEnabled { ;Boolean => Determines the ability of the end users to use pinching motions on touch input enabled devices to scale the web content in the WebView2
            get => this.Settings.IsPinchZoomEnabled
            set => this.Settings.IsPinchZoomEnabled := Value
        }
        IsReputationCheckingRequired { ;Boolean => Determines whether SmartScreen is enabled when visiting web pages
            get => this.Settings.IsReputationCheckingRequired
            set => this.Settings.IsReputationCheckingRequired := Value
        }
        IsScriptEnabled { ;Boolean => Determines whether running JavaScript is enabled in all future navigations in the WebView
            get => this.Settings.IsScriptEnabled
            set => this.Settings.IsScriptEnabled := Value
        }
        IsStatusBarEnabled { ;Boolean => Determines whether the status bar is displayed
            get => this.Settings.IsStatusBarEnabled
            set => this.Settings.IsStatusBarEnabled := Value
        }
        IsSwipeNavigationEnabled { ;Boolean => Determines whether the end user to use swiping gesture on touch input enabled devices to navigate in WebView2
            get => this.Settings.IsSwipeNavigationEnabled
            set => this.Settings.IsSwipeNavigationEnabled := Value
        }
        IsWebMessageEnabled { ;Boolean => Determines whether communication from the host to the top-level HTML document of the WebView is allowed
            get => this.Settings.IsWebMessageEnabled
            set => this.Settings.IsWebMessageEnabled := Value
        }
        IsZoomControlEnabled { ;Boolean => Determines whether the user is able to impact the zoom of the WebView
            get => this.Settings.IsZoomControlEnabled
            set => this.Settings.IsZoomControlEnabled := Value
        }
        UserAgent { ;String => Determines WebView2's User Agent
            get => this.Settings.UserAgent
            set => this.Settings.UserAgent := Value
        }

    Source => this.wv.Source ;Returns Uri of current page
    NavigateToString(HtmlContent) => this.wv.NavigateToString(HtmlContent) ;Navigate to text (essentially create a webpage from a string)
    AddScriptToExecuteOnDocumentCreatedAsync(JavaScript) => this.wv.AddScriptToExecuteOnDocumentCreatedAsync(JavaScript) ;Adds JavaScript to run when the DOM is created
    AddScriptToExecuteOnDocumentCreated(JavaScript) {
        AddScriptToExecuteOnDocumentCreatedPromise := this.wv.AddScriptToExecuteOnDocumentCreatedAsync(JavaScript)
        AddScriptToExecuteOnDocumentCreatedPromise.await()
        return Trim(AddScriptToExecuteOnDocumentCreatedPromise.Result, "`"")
    }
    RemoveScriptToExecuteOnDocumentCreated(Id) => this.wv.RemoveScriptToExecuteOnDocumentCreated(Id)
    ExecuteScriptAsync(JavaScript) => this.wv.ExecuteScriptAsync(JavaScript) ;Execute code on the current Webpage
    ExecuteScript(JavaScript, Timeout := -1) {
        ExecuteScriptPromise := this.wv.ExecuteScriptAsync(JavaScript)
        try {
            ExecuteScriptPromise.await(Timeout)
        } catch {
            ExecuteScriptPromise.Result := "Timeout Error"
        }
        return Trim(ExecuteScriptPromise.Result, "`"")
    }
    CapturePreviewAsync(ImageFormat, ImageStream) => this.wv.CapturePreviewAsync(ImageFormat, ImageStream) ;Take a "screenshot" of the current WebView2 content
    CapturePreview(ImageFormat, ImageStream) {
        CapturePreviewPromise := this.wv.CapturePreviewAsync(ImageFormat, ImageStream)
        CapturePreviewPromise.await()
        return CapturePreviewPromise.Result
    }
    Reload() => this.wv.Reload() ;Reloads the current page

    /**
     * In order to use PostWebMessageAsJson() or PostWebMessageAsString(), you'll need to setup your webpage to listen to messages
     * First, MyWindow.Settings.IsWebMessageEnabled must be set to true
     * On your webpage itself, you'll need to setup an EventListner and Handler for the WebMessages
     *     window.chrome.webview.addEventListener('message', ahkWebMessage);
     *     function ahkWebMessage(Msg) {
     *         console.log(Msg);
     *     }
    **/
    PostWebMessageAsJson(WebMessageAsJson) => this.wv.PostWebMessageAsJson(WebMessageAsJson) ;Posts the specified JSON message to the top level document in this WebView
    PostWebMessageAsString(WebMessageAsString) => this.wv.PostWebMessageAsString(WebMessageAsString) ;Posts the specified STRING message to the top level document in this WebView
    CallDevToolsProtocolMethodAsync(MethodName, ParametersAsJson) => this.wv.CallDevToolsProtocolMethodAsync(MethodName, ParametersAsJson) ;Runs an DevToolsProtocol method

    /**
     * @returns {Boolean} The process ID of the browser process that hosts the WebView2.
     * @see {@link https://learn.microsoft.com/en-us/dotnet/api/microsoft.web.webview2.core.corewebview2.browserprocessid|BrowserProcessId}
     */
    BrowserProcessId => this.wv.BrowserProcessId ;Returns the process ID of the browser process that hosts the WebView2

    CanGoBack => this.wv.CanGoBack ;Returns true if the WebView is able to navigate to a previous page in the navigation history
    CanGoForward => this.wv.CanGoForward ;Returns true if the WebView is able to navigate to a next page in the navigation history

    /**
     * Navigates the WebView to the previous page in the navigation history.
     * @see {@link https://learn.microsoft.com/en-us/dotnet/api/microsoft.web.webview2.core.corewebview2.goback|GoBack}
     */
    GoBack() => this.wv.GoBack() ;GoBack to the previous page in the navigation history
    GoForward() => this.wv.GoForward() ;GoForward to the next page in the navigation history
    GetDevToolsProtocolEventReceiver(EventName) => this.wv.GetDevToolsProtocolEventReceiver(EventName) ;Gets a DevTools Protocol event receiver that allows you to subscribe to a DevToolsProtocol event
    Stop() => this.wv.Stop() ;Stops all navigations and pending resource fetches
    DocumentTitle => this.wv.DocumentTitle ;Returns the DocumentTitle of the current webpage
    AddHostObjectToScript(ObjName, Obj) => this.wv.AddHostObjectToScript(ObjName, Obj) ;Create object link between the WebView2 and the AHK Script
    RemoveHostObjectFromScript(ObjName) => this.wv.RemoveHostObjectFromScript(ObjName) ;Delete object link from the WebView2
    OpenDevToolsWindow() => this.wv.OpenDevToolsWindow() ;Opens DevTools for the current WebView2
    ContainsFullScreenElement => this.wv.ContainsFullScreenElement ;Returns true if the WebView contains a fullscreen HTML element
    AddWebResourceRequestedFilter(Uri, ResourceContext) => this.wv.AddWebResourceRequestedFilter(Uri, ResourceContext) ;Adds a URI and resource context filter for the WebResourceRequested event
    RemoveWebResourceRequestedFilter(Uri, ResourceContext) => this.wv.RemoveWebResourceRequestedFilter(Uri, ResourceContext) ;Removes a matching WebResource filter that was previously added for the WebResourceRequested event
    NavigateWithWebResourceRequest(Request) => this.wv.NavigateWithWebResourceRequest(Request) ;Navigates using a constructed CoreWebView2WebResourceRequest object
    CookieManager => this.wv.CookieManager ;Gets the CoreWebView2CookieManager object associated with this CoreWebView2
        GetCookiesAsync(Uri) => this.CookieManager.GetCookies(Uri) ;Gets a list of cookies matching the specific URI

    Environment => this.wv.Environment ;Returns Map() of Environment settings
        CreateCoreWebView2ControllerAsync(ParentWindow) => this.Environment.CreateWebView2ControllerAsync(ParentWindow)
        CreateWebResourceResponse(Content, StatusCode, ReasonPhrase, Headers) => this.Environment.CreateWebResourceResponse(Content, StatusCode, ReasonPhrase, Headers)
        BrowserVersionString => this.Environment.BrowserVersionString ;Returns the browser version info of the current CoreWebView2Environment, including channel name if it is not the stable channel
        FailureReportFolderPath => this.Environment.FailureReportFolderPath ;Returns the failure report folder that all CoreWebView2s created from this environment are using
        UserDataFolder => this.Environment.UserDataFolder ;Returns the user data folder that all CoreWebView2s created from this environment are using
        CreateWebResourceRequest(Uri, Method, PostData, Headers) => this.Environment.CreateWebResourceRequest(Uri, Method, PostData, Headers) ;Creates a new CoreWebView2WebResourceRequest object
        CreateCoreWebView2CompositionControllerAsync(ParentWindow) => this.Environment.CreateCoreWebView2CompositionControllerAsync(ParentWindow) ;Creates a new WebView for use with visual hosting
        CreateCoreWebView2PointerInfo() => this.Environment.CreateCoreWebView2PointerInfo() ;Returns Map() of a combined win32 POINTER_INFO, POINTER_TOUCH_INFO, and POINTER_PEN_INFO object
        GetAutomationProviderForWindow(Hwnd) => this.Environment.GetAutomationProviderForWindow(Hwnd) ;PRODUCES ERROR, REACH OUT TO THQBY
        CreatePrintSettings() => this.Environment.CreatePrintSettings() ;Creates the CoreWebView2PrintSettings used by the PrintToPdfAsync(String, CoreWebView2PrintSettings) method
        GetProcessInfos() => this.Environment.GetProcessInfos() ;Returns the list of all CoreWebView2ProcessInfo using same user data folder except for crashpad process
        CreateContextMenuItem(Label, IconStream, Kind) => this.Environment.CreateContextMenuItem(Label, IconStream, Kind) ;PRODUCES ERROR, REACH OUT TO THQBY
        CreateCoreWebView2ControllerOptions() => this.Environment.CreateCoreWebView2ControllerOptions() ;PRODUCES ERROR, REACH OUT TO THQBY
        CreateCoreWebView2ControllerWithOptionsAsync(ParentWindow, Options) => this.Environment.CreateCoreWebView2ControllerWithOptionsAsync(ParentWindow, Options) ;PRODUCES ERROR, REACH OUT TO THQBY -- I think the issue is part of the `CreateCoreWEbView2ControllerOptions()` method
        CreateCoreWebView2CompositionControllerWithOptionsAsync(ParentWindow, Options) => this.Environment.CreateCoreWebView2CompositionControllerWithOptionsAsync(ParentWindow, Options) ;PRODUCES ERROR, REACH OUT TO THQBY -- I think the issue is part of the `CreateCoreWEbView2ControllerOptions()` method
        CreateSharedBuffer(Size) => this.Environment.CreateSharedBuffer(Size) ;Create a shared memory based buffer with the specified size in bytes -- PRODUCES ERROR, REACH OUT TO THQBY

    TrySuspendAsync() => this.wv.TrySuspendAsync() ;Must set `IsVisible := 0` before trying to call
    Resume() => this.wv.Resume() ;Resumes the WebView so that it resumes activities on the web page. Will fail unless you set `IsVisible := 1`
    IsSuspended => this.wv.IsSuspended ;Returns true if the WebView is suspended
    SetVirtualHostNameToFolderMapping(HostName, FolderPath, AccessKind) => this.wv.SetVirtualHostNameToFolderMapping(HostName, FolderPath, AccessKind) ;Sets a mapping between a virtual host name and a folder path to make available to web sites via that host name
    ClearVirtualHostNameToFolderMapping(HostName) => this.wv.ClearVirtualHostNameToFolderMapping(HostName) ;Clears a host name mapping for local folder that was added by SetVirtualHostNameToFolderMapping()
    OpenTaskManagerWindow() => this.wv.OpenTaskManagerWindow() ;Opens the Browser Task Manager view as a new window in the foreground
    IsMuted { ;Indicates whether all audio output from this CoreWebView2 is muted or not. Set to true will mute this CoreWebView2, and set to false will unmute this CoreWebView2. true if audio is muted
        get => this.wv.IsMuted
        set => this.wv.IsMuted := Value
    }
    IsDocumentPlayingAudio => this.wv.IsDocumentPlayingAudio ;Returns true if audio is playing even if IsMuted is true
    IsDefaultDownloadDialogOpen => this.wv.IsDefaultDownloadDialogOpen ;Returns true if the default download dialog is currently open
    OpenDefaultDownloadDialog() => this.wv.OpenDefaultDownloadDialog() ;Opens the DownloadDialog Popup Window
    CloseDefaultDownloadDialog() => this.wv.CloseDefaultDownloadDialog() ;Closes the DownloadDialog Popup Window
    DefaultDownloadDialogCornerAlignment { ;Position of DownloadDialog does not update until after the WebView2 position or size has changed
        get => this.wv.DefaultDownloadDialogCornerAlignment ;Return the current corner the DownloadDialog will show up in (0 := TopLeft, 1 := TopRight, 2 := BottomLeft, 3 := BottomRight)
        set => this.wv.DefaultDownloadDialogCornerAlignment := Value ;Set the corner of the WebView2 that the DownloadDialog will show up in (0 := TopLeft, 1 := TopRight, 2 := BottomLeft, 3 := BottomRight)
    }
    DefaultDownloadDialogMargin { ;Working, but I don't know how to accurately assign a new Margin yet. We can assign one via an Integer, but it's hit and miss to get the position correct
        get => this.wv.DefaultDownloadDialogMargin
        set => this.wv.DefaultDownloadDialogMargin := Value
    }
    CallDevToolsProtocolMethodForSessionAsync(SessionId, MethodName, ParametersAsJson) => this.wv.CallDevToolsProtocolMethodForSessionAsync(SessionId, MethodName, ParametersAsJson) ;Runs a DevToolsProtocol method for a specific session of an attached target
    StatusBarText => this.wv.StatusBarText ;Returns the current text of the WebView2 StatusBar
    Profile => this.wv.Profile ;Returns the associated CoreWebView2Profile object of CoreWebView2
    ClearServerCertificateErrorActionsAsync() => this.wv.ClearServerCertificateErrorActionsAsync()
    FaviconUri => this.wv.FaviconUri ;Returns the Uri as a string of the current Favicon. This will be an empty string if the page does not have a Favicon
    GetFaviconAsync(Format) => this.wv.GetFaviconAsync(Format) ;Get the downloaded Favicon image for the current page and copy it to the image stream
    PrintAsync(PrintSettings) => this.wv.PrintAsync(PrintSettings) ;Print the current web page asynchronously to the specified printer with the provided settings
    PrintToPdfAsync(ResultFilePath, PrintSettings) => this.wv.PrintToPdfAsync(ResultFilePath, PrintSettings) ;Print the current page to PDF with the provided settings
    ShowPrintUI(PrintDialogKind) => this.wv.ShowPrintUI(PrintDialogKind) ;Opens the print dialog to print the current web page. Browser printDialogKind := 0, System printDialogKind := 1
    PrintToPdfStreamAsync(PrintSettings) => this.wv.PrintToPdfStreamAsync(PrintSettings) ;Provides the PDF data of current web page for the provided settings to a Stream
    PostSharedBufferToScript(SharedBuffer, Access, AdditionalDataAsJson) => this.wv.PostSharedBufferToScript(SharedBuffer, Access, AdditionalDataAsJson) ;Share a shared buffer object with script of the main frame in the WebView
    MemoryUsageTargetLevel { ;0 = Normal, 1 = Low; Low can be used for apps that are inactive to conserve memory usage
        get => this.wv.MemoryUsageTargetLevel
        set => this.wv.MemoryUsageTargetLevel := Value
    }

    ;-------------------------------------------------------------------------------------------
    ;Handler Assignments
    static PlaceholderHandler(Handler, ICoreWebView2, Args) {
        ;MsgBox(handler, "WebviewWindow.PlaceholderHandler()", "262144")
    }

    ;Controller
    ZoomFactorChanged(Handler) => this.wvc.add_ZoomFactorChanged(Handler)
    MoveFocusRequested(Handler) => this.wvc.add_MoveFocusRequested(Handler)
    GotFocus(Handler) => this.wvc.add_GotFocus(Handler)
    LostFocus(Handler) => this.wvc.add_LostFocus(Handler)
    AcceleratorKeyPressed(Handler) => this.wvc.add_AcceleratorKeyPressed(Handler)
    RasterizationScaleChanged(Handler) => this.wvc.add_RasterizationScaleChanged(Handler)

    ;Core
    NavigationStarting(Handler) => this.wv.add_NavigationStarting(Handler)
    ContentLoading(Handler) => this.wv.add_ContentLoading(Handler)
    SourceChanged(Handler) => this.wv.add_SourceChanged(Handler)
    HistoryChanged(Handler) => this.wv.add_HistoryChanged(Handler)
    NavigationCompleted(Handler) => this.wv.add_NavigationCompleted(Handler)
    ScriptDialogOpening(Handler) => this.wv.add_ScriptDialogOpening(Handler)
    PermissionRequested(Handler) => this.wv.add_PermissionRequested(Handler)
    ProcessFailed(Handler) => this.wv.add_ProcessFailed(Handler)
    WebMessageReceived(Handler) => this.wv.add_WebMessageReceived(Handler)
    NewWindowRequested(Handler) => this.wv.add_NewWindowRequested(Handler)
    DocumentTitleChanged(Handler) => this.wv.add_DocumentTitleChanged(Handler)
    ContainsFullScreenElementChanged(Handler) => this.wv.add_ContainsFullScreenElementChanged(Handler)
    WebResourceRequested(Handler) => this.wv.add_WebResourceRequested(Handler)
    WindowCloseRequested(Handler) => this.wv.add_WindowCloseRequested(Handler)
    WebResourceResponseReceived(Handler) => this.wv.add_WebResourceResponseReceived(Handler)
    DOMContentLoaded(Handler) => this.wv.add_DOMContentLoaded(Handler)
    FrameCreated(Handler) => this.wv.add_FrameCreated(Handler)
    DownloadStarting(Handler) => this.wv.add_ownloadStarting(Handler)
    ClientCertificateRequested(Handler) => this.wv.add_ClientCertificateRequested(Handler)
    IsMutedChanged(Handler) => this.wv.add_IsMutedChanged(Handler)
    IsDocumentPlayingAudioChanged(Handler) => this.wv.add_IsDocumentPlayingAudioChanged(Handler)
    IsDefaultDownloadDialogOpenChanged(Handler) => this.wv.add_IsDefaultDownloadDialogOpenChanged(Handler)
    BasicAuthenticationRequested(Handler) => this.wv.add_BasicAuthenticationRequested(Handler)
    ContextMenuRequested(Handler) => this.wv.add_ContextMenuRequested(Handler)
    StatusBarTextChanged(Handler) => this.wv.add_StatusBarTextChanged(Handler)
    ServerCertificateErrorDetected(Handler) => this.wv.add_ServerCertificateErrorDetected(Handler)
    FaviconChanged(Handler) => this.wv.add_FaviconChanged(Handler)
    LaunchingExternalUriScheme(Handler) => this.wv.add_LaunchingExternalUriScheme(Handler)
}
