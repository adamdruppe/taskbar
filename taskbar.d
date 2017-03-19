/********************************************************
	My small hacked panel 2.0
	Originally based on fspanel by Peter Zelezny
	with some code from Docker  by Ben Jansens

	Heavily changed by me, Adam D. Ruppe, in 2007
	Ported to D by me in 2014.

	License: GPL
	Dependencies: simpledisplay.d and color.d from
	              https://github.com/adamdruppe/arsd
*********************************************************/

/*
	I want to add notification support like
	xfce4-notifyd but done with my own thing
	so there's like an icon and a history.
*/

pragma(lib, "Xpm");
import arsd.simpledisplay;

import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.time;
import core.sys.posix.sys.time;
import core.sys.posix.unistd;

struct task {
	task *next;
	Window win;
	Pixmap icon;
	Pixmap mask;
	char* _name;
	@property char* name() { return _name; }
	@property char* name(char* v) {
		auto o = v;
		if(v !is null)
		while(*v) {
			if(*v > 127) {
				auto n = v;
				while(*n) {
					*n = *(n+1);
					n++;
				}
			} else {
				v++;
			}
		}
		return _name = o;
	}
	bool using_fallback_name;
	int pos_x;
	int width;
//	arch_ulong desktop; // me
	bool focused;
	bool iconified;
//	bool shaded; // me
	bool icon_copied;
	bool demands_attention; // me

	bool using_old_style_icon;
}

int clockPosition() {
	return WINWIDTH - time_width - (TEXTPAD * 4);
}

version=WithNotificationArea;

version(WithNotificationArea)
	int notificationAreaPosition() {
		auto current = icons;
		int count = 0;
		while(current) {
			count++;
			current = current.next;
		}

		return clockPosition() - count * ICONWIDTH;
	}
else
	alias notificationAreaPosition = clockPosition;

version(WithNotificationArea) {
	struct NotificationAreaIcon {
		Window id;
		int x;

		NotificationAreaIcon* next;
	}
	NotificationAreaIcon* icons;

	// some of this code is borrowed from Docker

	Atom net_opcode_atom;
	Window net_sel_win;

	static Atom net_message_data_atom;

	void net_init() {
		import std.string; import std.conv;

		auto net_sel_atom = XInternAtom(dd, cast(char*)(format("_NET_SYSTEM_TRAY_S%d", DefaultScreen(dd)).ptr), false);
		assert(net_sel_atom);
		net_opcode_atom = XInternAtom(dd, "_NET_SYSTEM_TRAY_OPCODE", false);
		assert(net_opcode_atom);
		auto net_manager_atom = XInternAtom(dd, "MANAGER", false);
		assert(net_manager_atom);
		net_message_data_atom = XInternAtom(dd, "_NET_SYSTEM_TRAY_MESSAGE_DATA", false);
		assert(net_message_data_atom);

		net_sel_win = XCreateSimpleWindow(dd, root_win, -1, -1, 1, 1, 0, 0, 0);
		assert(net_sel_win);

		XSetSelectionOwner(dd, net_sel_atom, net_sel_win, CurrentTime);
		if (XGetSelectionOwner(dd, net_sel_atom) != net_sel_win)
			return; /* we don't get the selection */

		XEvent m;
		m.type = EventType.ClientMessage;
		m.xclient.message_type = net_manager_atom;
		m.xclient.format = 32;
		m.xclient.data.l[0] = CurrentTime;
		m.xclient.data.l[1] = net_sel_atom;
		m.xclient.data.l[2] = net_sel_win;
		m.xclient.data.l[3] = 0;
		m.xclient.data.l[4] = 0;
		XSendEvent(dd, root_win, false, EventMask.StructureNotifyMask, &m);
	}

	void net_destroy() {
		XDestroyWindow(dd, net_sel_win);
		net_sel_win = None;
	}

	void net_message(taskbar* tb, XClientMessageEvent *e) {
		arch_ulong opcode;
		Window id;

		assert(e);

		opcode = e.data.l[1];

		switch (opcode) {
			case SYSTEM_TRAY_REQUEST_DOCK: /* dock a new icon */
				id = e.data.l[2];
				if (id) {
					icon_add(tb, id);
					import std.stdio; writefln("Window %x", id);
					XSelectInput(dd, id, EventMask.StructureNotifyMask);
				}
			break;

			case SYSTEM_TRAY_BEGIN_MESSAGE:
				id = e.window;
			break;

			case SYSTEM_TRAY_CANCEL_MESSAGE:
				id = e.window;
			break;

			default:
				if (opcode == net_message_data_atom) {
					// writefln("Text For Message From Dockapp:\n%s\n", e->data.b);
					id = e.window;
					break;
				}
			break;
		}
	}

	void net_icon_remove(NotificationAreaIcon *notification_area_window) {
		assert(notification_area_window);
		XSelectInput(dd, notification_area_window.id, EventMask.NoEventMask);
	}


	/*
	  The notification_area_window must have its id set.
	*/
	void icon_add(taskbar* tb, Window id) {
		NotificationAreaIcon *notification_area_window;

		assert(id);

		notification_area_window = new NotificationAreaIcon;
		notification_area_window.id = id;

		XReparentWindow(dd, notification_area_window.id, tb.win, 0, 0);

		/* find the positon for the systray app window */
		notification_area_window.x = 0 /* currentWidth */;

		notification_area_window.next = icons;
		icons = notification_area_window;

		/* watch for the icon trying to resize itself! BAD ICON! BAD! */
		//XSelectInput(dd, notification_area_window.id, StructureNotifyMask);

		/* position and size the icon window */
		XMoveResizeWindow(dd, notification_area_window.id,
				notification_area_window.x, 0, ICONWIDTH, ICONHEIGHT);

		/* show the window */
		XMapRaised(dd, notification_area_window.id);

		reposition_icons();
	}

	void reposition_icons() {
		auto current = icons;
		auto pos = notificationAreaPosition();
		while(current) {
			current.x = pos;

			XMoveWindow(dd, current.id, current.x, 0);

			current = current.next;
			pos += ICONWIDTH;
		}
	}


	void icon_remove(NotificationAreaIcon *node) {
		XErrorHandler old;
		NotificationAreaIcon *notification_area_window = node;
		Window notification_area_window_id = notification_area_window.id;

		net_icon_remove(notification_area_window);

		XSelectInput(dd, notification_area_window.id, EventMask.NoEventMask);

		NotificationAreaIcon* prev;
		auto current = icons;
		while(current) {
			if(current is node) {
				if(prev is null)
					icons = current.next;
				else
					prev.next = current.next;
				break;
			}
			prev = current;
			current = current.next;
		}

		/* reparent it to root */
		XReparentWindow(dd, notification_area_window_id, root_win, 0, 0);

		reposition_icons();
	}
}

struct taskbar {
	Window win;
	task* task_list;
	int num_tasks;
	int my_desktop;

	void drawClock() {
		int x = clockPosition();
		int width = WINWIDTH - x - 2;

		auto now = time(null);
		auto time_str = ctime(&now) + 11;

		x += TEXTPAD;
		set_foreground (0);
		fill_rect(&this, x + 1, 2, width - (TEXTPAD * 2) - 1, WINHEIGHT - 4);
		set_foreground (5);
		XDrawString(dd, this.win, fore_gc, x + TEXTPAD - 1, text_y, time_str, 5);
	}

}

/* XPM */
static immutable(char*[]) icon_xpm = [
"16 16 16 1",
" 	c None",
".	c #323232",
"+	c #535353",
"@	c #4A8A8E",
"#	c #DEE2E2",
"$	c #7E827A",
"%	c #8A9292",
"&	c #D6D6D6",
"*	c #36767E",
"=	c #9E9E9E",
"-	c #FAFAFA",
";	c #B2B2B2",
">	c #DEEEEA",
",	c #464646",
"'	c #5EA2A2",
")	c #52969A",
"                ",
"                ",
" --#>>>>>>#-#-; ",
" -&%')))))=&=&+ ",
" >;$@*****=;%;+ ",
" &$$$$$$$$$$$$, ",
" &;;;;;;;;;;;;+ ",
" &;;;;;;;;;;;;+ ",
" #;;;;;;;;;;;;+ ",
" &;;;;;;;;;;;;+ ",
" #;;;;;;;;;;;;+ ",
" #;;;;;;;;;;;;+ ",
" &;;;;;;;;;;;;+ ",
" $............. ",
"                ",
"                "];

/* you can edit these */

enum time_width = (35);
enum MAX_TASK_WIDTH = 145;//WINWIDTH
/* If you like your buttons to take all available space, use this instead: */
//#define MAX_TASK_WIDTH WINWIDTH

enum ICONWIDTH = 16;
enum ICONHEIGHT = 16;
enum WINHEIGHT = 16;//24
auto WINWIDTH() { return (scr_width == 2560) ? 1280 : scr_width; }
enum XPOS = 0;
auto YPOS() { return (scr_height - WINHEIGHT); }
enum FONT_NAME = "-*-lucida*-m*-r-*-*-12-*-*";


/* don't edit these */
enum TEXTPAD = 6;

Display *dd;
Window root_win;
Pixmap generic_icon;
Pixmap generic_mask;
GC fore_gc;
XFontStruct *xfs;
int scr_screen;
int scr_depth;
int scr_width;
int scr_height;
int text_y;
enum ushort[] cols = [
/**/	0x0000, 0x0000, 0x3333,		  /* 0. */
/**/	0x0000, 0x0000, 0x8888,		  /* 1. */
	0x3333, 0x3333, 0x3333,		  /* 2. */
/**/	0x3333, 0x7878, 0x3333,		  /* 3. */
/**/	0x8617, 0x8207, 0x8617,		  /* 4. */
	0xd9d9, 0xd9d9, 0xd9d9,		  /* 5. */
	0x0000, 0x8888, 0x0000		  /* 6. */
];
/*
	Color meanings:

	0: background and clock background
	1: activated window background (used to also be clock background, but isn't anymore), line across the bottom of tasks
	2: not used anymore
	3: outline of buttons for 3d look (line across top), offset color for shaded windows
	4: minor outline of buttons, deactivated window text
	5: normal text
	6: urgent window (not yet implemented)

*/

enum PALETTE_COUNT = cols.length / 3;

arch_ulong palette[PALETTE_COUNT];

enum immutable(char*[]) atom_names = [
	"_NET_CURRENT_DESKTOP",
	"_NET_CLIENT_LIST",
	"WM_STATE",
	"_NET_CLOSE_WINDOW",
	"_NET_ACTIVE_WINDOW",
	"_NET_WM_DESKTOP",
	"_NET_WM_WINDOW_TYPE",
	"_NET_WM_WINDOW_TYPE_DOCK",

	"_NET_WM_STATE",
	"_NET_WM_STATE_SHADED",
	"_NET_WM_STATE_SKIP_TASKBAR",
//	"_NET_WM_STATE_HIDDEN",
	"_NET_WM_STATE_DEMANDS_ATTENTION",
	"_NET_WM_ICON",
	"_NET_WM_NAME",
	"UTF8_STRING"
];

enum ATOM_COUNT = atom_names.length;

Atom atoms[ATOM_COUNT];

auto atom__NET_CURRENT_DESKTOP() { return atoms[0]; }
auto atom__NET_CLIENT_LIST() { return atoms[1]; }
auto atom_WM_STATE() { return atoms[2]; }
auto atom__NET_CLOSE_WINDOW() { return atoms[3]; }
auto atom__NET_ACTIVE_WINDOW() { return atoms[4]; }
auto atom__NET_WM_DESKTOP() { return atoms[5]; }
auto atom__NET_WM_WINDOW_TYPE() { return atoms[6]; }
auto atom__NET_WM_WINDOW_TYPE_DOCK() { return atoms[7]; }

auto atom__NET_WM_STATE() { return atoms[8]; }
auto atom__NET_WM_STATE_SHADED() { return atoms[9]; }
auto atom__NET_WM_STATE_SKIP_TASKBAR() { return atoms[10]; }
auto atom__NET_WM_STATE_DEMANDS_ATTENTION() { return atoms[11]; } // something doesn't work with my implementation
auto atom_NET_WM_ICON() { return atoms[12]; }
auto atom_NET_WM_NAME() { return atoms[13]; }
auto atom_UTF8_STRING() { return atoms[14]; }


/* Originally from wmctrl by Tomas Styblo */
static int client_msg(Window win, Atom msg, arch_ulong data0, arch_ulong data1, arch_ulong data2, arch_ulong data3, arch_ulong data4) {
    XEvent event;
    arch_long mask = EventMask.SubstructureRedirectMask | EventMask.SubstructureNotifyMask;

    event.xclient.type = EventType.ClientMessage;
    event.xclient.serial = 0;
    event.xclient.send_event = true;
    event.xclient.message_type = msg;
    event.xclient.window = win;
    event.xclient.format = 32;
    event.xclient.data.l[0] = data0;
    event.xclient.data.l[1] = data1;
    event.xclient.data.l[2] = data2;
    event.xclient.data.l[3] = data3;
    event.xclient.data.l[4] = data4;
    
    if (XSendEvent(dd, root_win, false, mask, &event)) {
        return EXIT_SUCCESS;
    }
    else {
        return EXIT_FAILURE;
    }
}//////////////

void * get_prop_data (Window win, Atom prop, Atom type, int *items) {
	Atom type_ret;
	int format_ret;
	arch_ulong items_ret;
	arch_ulong after_ret;
	ubyte *prop_data;

	XGetWindowProperty (dd, win, prop, 0, 0x7fffffff, false, type, &type_ret, &format_ret, &items_ret, &after_ret, cast(void**) &prop_data);
	if (items)
		*items = items_ret;

	return prop_data;
}

void set_foreground (int index) {
	XSetForeground (dd, fore_gc, palette[index]);
}

void draw_line (taskbar *tb, int x, int y, int a, int b) {
	XDrawLine (dd, tb.win, fore_gc, x, y, a, b);
}

void fill_rect (taskbar *tb, int x, int y, int a, int b) {
	XFillRectangle (dd, tb.win, fore_gc, x, y, a, b);
}

void scale_icon (task *tk) {
	uint xx, yy, d, bw, w, h;
	int x, y;
	Pixmap pix, mk = None;
	XGCValues gcv;
	GC mgc;

	XGetGeometry (dd, tk.icon, &pix, &x, &y, &w, &h, &bw, &d);
	pix = XCreatePixmap (dd, tk.win, ICONWIDTH, ICONHEIGHT, scr_depth);

	if (tk.mask != None) {
		mk = XCreatePixmap (dd, tk.win, ICONWIDTH, ICONHEIGHT, 1);
		gcv.subwindow_mode = IncludeInferiors;
		gcv.graphics_exposures = false;
		mgc = XCreateGC (dd, mk, GCGraphicsExposures | GCSubwindowMode, &gcv);
	}

	set_foreground (5 /*3*/);

	/* this is my simple & dirty scaling routine */
	for (y = ICONHEIGHT - 1; y >= 0; y--) {
		yy = (y * h) / ICONHEIGHT;
		for (x = ICONWIDTH - 1; x >= 0; x--) {
			xx = (x * w) / ICONWIDTH;
			if (d != scr_depth) {
				XCopyPlane (dd, tk.icon, pix, fore_gc, xx, yy, 1, 1, x, y, 1);
			} else
				XCopyArea (dd, tk.icon, pix, fore_gc, xx, yy, 1, 1, x, y);
			if (mk != None)
				XCopyArea (dd, tk.mask, mk, mgc, xx, yy, 1, 1, x, y);
		}
	}

	if (mk != None) {
		XFreeGC (dd, mgc);
		tk.mask = mk;
	}

	tk.icon = pix;
}

void get_task_hinticon (task *tk) {
	tk.icon = None;
	tk.mask = None;

	auto hin = cast(XWMHints *) get_prop_data (tk.win, XA_WM_HINTS, XA_WM_HINTS, null);
	if (hin) {
		if ((hin.flags & IconPixmapHint)) {
			if ((hin.flags & IconMaskHint)) {
				tk.mask = hin.icon_mask;
			}

			tk.icon = hin.icon_pixmap;
			tk.icon_copied = 1;
			scale_icon (tk);
		}
		XFree (hin);
	}

	if (tk.icon == None) {
		tk.icon_copied = 0;
		tk.icon = generic_icon;
		tk.mask = generic_mask;
	}
}

void get_task_netwmicon (task *tk) {
	auto originalItems = 0;
	auto originalData =  cast(arch_ulong*) get_prop_data (tk.win, atom_NET_WM_ICON, XA_CARDINAL, &originalItems);
	bool fallback = false;

	try_again:

	int items = originalItems;
	auto data = originalData;

	if (data && items > 2) {
		// these are an array of rgba images that we have to convert into pixmaps ourself
		int loc = 0;

		while(items > 0) {

			int width = data[0];
			int height = data[1];
			items -= 2;
			loc += 2;

			if(fallback || (width == ICONWIDTH && height == ICONHEIGHT)) {

				arch_ulong* rawData = cast(arch_ulong*) malloc(width * height * arch_long.sizeof);
				auto rawDataLength = width * height * arch_long.sizeof;
				for(int i = 0; i < width * height; i++)
					rawData[i] = data[loc + i];

				immutable originalWidth = width;
				immutable originalHeight = height;

				XImage* handle = XCreateImage(dd, DefaultVisual(dd, DefaultScreen(dd)), 24, cast(int) ImageFormat.ZPixmap, 0, cast(ubyte*)rawData, width, height, 8, arch_ulong.sizeof*width);
				if(handle == null)
					exit(1);

				if(fallback) {
					// if the provided image is smaller than we need, no big deal, we'll just center it below
					if(width <= ICONWIDTH && height <= ICONHEIGHT)
						goto use_it;

					// but if the provided image is larger, we need to scale it down

					// my scaling algorithm is to just average each byte in the rows, then columns, and bring them in.

					// the first one we see ought to be the smallest one btw, which is what we want - speed > quality

					if(width > ICONWIDTH && height > ICONHEIGHT) {
						auto bytes = (cast(ubyte*) rawData)[0 .. originalWidth * originalHeight * arch_ulong.sizeof];

						import imagescale;
						downscaleImage(bytes, originalWidth, originalHeight, ICONWIDTH, ICONHEIGHT, arch_ulong.sizeof);

						width = ICONWIDTH;
						height = ICONHEIGHT;
					} else goto dont_use_it;
				}

				use_it:

				Pixmap icon;
				Pixmap mask;

				icon = XCreatePixmap(dd, tk.win, ICONWIDTH, ICONHEIGHT, 24);
				XFillRectangle(dd, icon, DefaultGC(dd, DefaultScreen(dd)), 0, 0, ICONWIDTH, ICONHEIGHT);
				XPutImage(dd, icon, DefaultGC(dd, DefaultScreen(dd)), handle, 0, 0, (ICONWIDTH - width) / 2, (ICONHEIGHT - height) / 2, ICONWIDTH, ICONHEIGHT);

				// Making the transparency mask. If the opacity is more than half, we consider it a set pixel
				// otherwise, make it transparent

				// this has to be malloced because otherwise XDestroyImage complains about invalid pointer; it apparently calls free() on it.
				auto maskData = (cast(ubyte*) malloc(ICONWIDTH * ICONHEIGHT / 8))[0 .. ICONWIDTH * ICONHEIGHT / 8];
				maskData[] = 0;
				foreach(y; 0 .. ICONHEIGHT)
				foreach(x; 0 .. ICONWIDTH) {
					auto idx = y * originalWidth + x;
					arch_ulong value = 0;
					if(idx < rawDataLength)
						value = rawData[idx];
					maskData[(y * ICONWIDTH + x) / 8] |= ((value & 0xff000000) > 0x80000000) ? (1 << (x % 8)) : 0;
				}
				auto handle2 = XCreateImage(dd, DefaultVisual(dd, DefaultScreen(dd)), 1, cast(int) ImageFormat.ZPixmap, 0, maskData.ptr, ICONWIDTH, ICONHEIGHT, 16, ICONWIDTH / 8);
				assert(handle2 !is null);
				mask = XCreatePixmap(dd, tk.win, ICONWIDTH, ICONHEIGHT, 1);
				auto gc = XCreateGC(dd, mask, 0, null);
				XPutImage(dd, mask, gc, handle2, 0, 0, 0, 0, ICONWIDTH, ICONHEIGHT);
				XFreeGC(dd, gc);
				XDestroyImage(handle2);

				XDestroyImage(handle);

				tk.icon = icon;
				tk.mask = mask;

				tk.icon_copied = 1;
				tk.using_old_style_icon = 0;

				goto success;
			}
			dont_use_it:
			loc += width * height;
			items -= width * height;
		}

		if(!fallback) {
			fallback = true;
			goto try_again;
		}

		success:

		XFree (data);
	}
}

arch_ulong find_desktop (Window win) {
	arch_ulong desk = 0;
	arch_ulong *data;

//	data = get_prop_data (win, atom__WIN_WORKSPACE, XA_CARDINAL, 0);
	if(win == root_win)
		data = cast(arch_ulong*) get_prop_data (win, atom__NET_CURRENT_DESKTOP, XA_CARDINAL, null);
	else
		data = cast(arch_ulong*) get_prop_data (win, atom__NET_WM_DESKTOP, XA_CARDINAL, null);
	if (data) {
		desk = *data;
		XFree (data);
	}
	return desk;
}

int is_iconified (Window win) {
	int ret = 0;

	auto data = cast(arch_ulong*) get_prop_data (win, atom_WM_STATE, atom_WM_STATE, null);
	if (data) {
		if (data[0] == IconicState)
			ret = 1;
		XFree (data);
	}

	return ret;
}

enum STATE_ICONIFIED =	1;
enum STATE_SHADED	=	2;
enum STATE_HIDDEN	=	4;
enum STATE_DEMANDS_ATTENTION = 8;

arch_ulong get_state(Window win) {
	Atom * data;
	int items,a;
	arch_ulong state = 0;
	data = cast(Atom*) get_prop_data (win, atom__NET_WM_STATE, XA_ATOM, &items);
	if (data) {
		for(a=0; a < items; a++) {
			if(data[a] == atom__NET_WM_STATE_SHADED)
				state |= STATE_SHADED;
			if(data[a] == atom__NET_WM_STATE_SKIP_TASKBAR)
				state |= STATE_HIDDEN;
			if(data[a] == atom__NET_WM_STATE_DEMANDS_ATTENTION)
				state |= STATE_DEMANDS_ATTENTION;
		}
		XFree (data);
	}

	if(is_iconified(win))
		state |= STATE_ICONIFIED;

	return state;

}

void add_task (taskbar * tb, Window win, bool focus){
	if (win == tb.win) return; /* Don't display the taskbar on the taskbar */

	/* is this window on a different desktop? */

	auto desk = find_desktop(win);

	/* Skip anything on a different desktop that is also NOT on all desktops */
	if (desk != 0xffffffff && tb.my_desktop != desk)
		return;

	auto state = get_state(win);
	if (state & STATE_HIDDEN)
		return;
	if((state & STATE_ICONIFIED) && !(state & STATE_SHADED))
		return;

	auto tk = cast(task*) calloc (1, task.sizeof);
	tk.win = win;
	tk.focused = focus;
	tk.name = cast(char*) get_prop_data (win, atom_NET_WM_NAME, atom_UTF8_STRING, null);
	if(tk.name is null || tk.name is null) {
		tk.name = cast(char*) get_prop_data (win, XA_WM_NAME, XA_STRING, null);
		tk.using_fallback_name = true;
	}
	tk.iconified = state & STATE_ICONIFIED;

	tk.demands_attention = !!(state & STATE_DEMANDS_ATTENTION);

	get_task_netwmicon(tk);
	if (tk.icon == None) {
		get_task_hinticon (tk);
		tk.using_old_style_icon = true;
	}

	XSelectInput (dd, win, EventMask.PropertyChangeMask | EventMask.FocusChangeMask | EventMask.StructureNotifyMask);

	/* now append it to our linked list */
	tb.num_tasks++;

	auto list = tb.task_list;
	if (!list) {
		tb.task_list = tk;
		return;
	}
	while (1) {
		if (!list.next) {
			list.next = tk;
			return;
		}
		list = list.next;
	}
}

void gui_sync () {
	XSync (dd, false);
}

void set_prop (Window win, Atom at, long val) {
	XChangeProperty (dd, win, at, XA_CARDINAL, 32, PropModeReplace, cast(ubyte *) &val, 1);
}

taskbar * gui_create_taskbar () {
	taskbar *tb;
	Window win;
	Atom type_atoms[1];

	XSizeHints size_hints;
	XSetWindowAttributes att;

	att.background_pixel = palette[0];
	att.event_mask = EventMask.ButtonPressMask | EventMask.ExposureMask;

	win = XCreateWindow (
				  /* display */ dd,
				  /* parent  */ root_win,
				  /* x       */ XPOS,
				  /* y       */ YPOS,
				  /* width   */ WINWIDTH,
				  /* height  */ WINHEIGHT,
				  /* border  */ 0,
				  /* depth   */ CopyFromParent,
				  /* class   */ InputOutput,
				  /* visual  */ cast(Visual*) CopyFromParent,
				  /*value mask*/ CWBackPixel | CWEventMask,
				  /* attribs */ &att);

	type_atoms[0] = atom__NET_WM_WINDOW_TYPE_DOCK;
	XChangeProperty(dd, win, atom__NET_WM_WINDOW_TYPE, XA_ATOM, 32, PropModeReplace, cast(ubyte*) type_atoms, 1);

	/* make sure the WM obeys our window position */
	size_hints.flags = PPosition;
	XSetWMNormalHints (dd, win, &size_hints);
/*
	XChangeProperty (dd, win, XA_WM_NORMAL_HINTS,
							XA_WM_SIZE_HINTS, 32, PropModeReplace,
							(ubyte *) &size_hints, sizeof (XSizeHints) / 4);
*/
	XMapWindow (dd, win);

	tb = cast(taskbar*) calloc (1, taskbar.sizeof);
	tb.win = win;

	return tb;
}

void gui_init () {
	XGCValues gcv;
	XColor xcl;
	int i, j;
	string fontname;

	i = j = 0;
	do {
		xcl.red = cols[i];
		i++;
		xcl.green = cols[i];
		i++;
		xcl.blue = cols[i];
		i++;
		XAllocColor (dd, DefaultColormap (dd, scr_screen), &xcl);
		palette[j] = xcl.pixel;
		j++;
	} while (j < PALETTE_COUNT);

	fontname = FONT_NAME;
	do {
		xfs = XLoadQueryFont (dd, fontname.ptr);
		fontname = "fixed";
	} while (!xfs);

	text_y = xfs.ascent + ((WINHEIGHT - xfs.ascent) / 2);

	gcv.font = xfs.fid;
	gcv.graphics_exposures = false;
	fore_gc = XCreateGC (dd, root_win, GCFont | GCGraphicsExposures, &gcv);

	XpmCreatePixmapFromData (dd, root_win, icon_xpm.ptr, &generic_icon, &generic_mask, null);
}

void gui_draw_vline (taskbar * tb, int x) {
	set_foreground (4);
	draw_line (tb, x, 0, x, WINHEIGHT);
	set_foreground (3);
	draw_line (tb, x + 1, 0, x + 1, WINHEIGHT);
}

void gui_draw_task (taskbar * tb, task * tk) {
	int len;
	int x = tk.pos_x;
	int taskw = tk.width;

	if (!tk.name)
		return;

	gui_draw_vline (tb, x);

/*set_foreground (3); *//* it's already 3 from gui_draw_vline() */
	draw_line (tb, x + 1, 0, x + taskw, 0);

	set_foreground (1);
	draw_line (tb, x + 1, WINHEIGHT - 1, x + taskw, WINHEIGHT - 1);

	if (tk.focused) {
		x++;
		/*set_foreground (1);*/		  /* mid gray */

		fill_rect (tb, x + 3, 3, taskw - 5, WINHEIGHT - 6);
		set_foreground (3);		  /* white */
		draw_line (tb, x + 2, WINHEIGHT - 2, x + taskw - 2, WINHEIGHT - 2);
		draw_line (tb, x + taskw - 2, 2, x + taskw - 2, WINHEIGHT - 2);
		set_foreground (0);
		draw_line (tb, x + 1, 2, x + 1, WINHEIGHT - 2);
		set_foreground (4);		  /* darkest gray */
		draw_line (tb, x + 2, 2, x + taskw - 2, 2);
		draw_line (tb, x + 2, 2, x + 2, WINHEIGHT - 3);
	} else {
		set_foreground (tk.demands_attention ? 6 : 0);		  /* mid gray */
		fill_rect (tb, x + 2, 1, taskw - 1, WINHEIGHT - 2);
	}

	{
		int text_x = x + TEXTPAD + TEXTPAD + ICONWIDTH;

		/* check how many chars can fit */
		len = strlen (tk.name);
		while (XTextWidth (xfs, tk.name, len) >= taskw - (text_x - x) - 2 && len > 0)
			len--;

		if (tk.iconified) {
			/* draw task's name dark (iconified) */
			set_foreground (3);
			XDrawString (dd, tb.win, fore_gc, text_x, text_y + 1, tk.name, len);
			set_foreground (4);
		} else {
			set_foreground (5);
		}

		/* draw task's name here */
		XDrawString (dd, tb.win, fore_gc, text_x, text_y, tk.name, len);

	}

	if (!tk.icon)
		return;

	/* draw the task's icon */
	XSetClipMask (dd, fore_gc, tk.mask);
	XSetClipOrigin (dd, fore_gc, x + TEXTPAD, (WINHEIGHT - ICONHEIGHT) / 2);
	XCopyArea (dd, tk.icon, tb.win, fore_gc, 0, 0, ICONWIDTH, ICONHEIGHT,
				  x + TEXTPAD, (WINHEIGHT - ICONHEIGHT) / 2);
	XSetClipMask (dd, fore_gc, None);
}

void gui_draw_taskbar(taskbar * tb) {
	auto width = notificationAreaPosition();
	auto x = 0;

	if(tb.num_tasks) {
		auto taskw = width / tb.num_tasks;
		if(taskw > MAX_TASK_WIDTH) {
			taskw = MAX_TASK_WIDTH;
		}

		auto tk = tb.task_list;
		while(tk) {
			tk.pos_x = x;
			tk.width = taskw - 1;
			gui_draw_task (tb, tk);
			x += taskw;
			tk = tk.next;
		}

		gui_draw_vline (tb, x);
	}

	set_foreground(0);
	fill_rect(tb, x + 2, 0, WINWIDTH, WINHEIGHT);

	tb.drawClock();
}

task* find_task(taskbar* tb, Window win) {
	auto list = tb.task_list;
	while (list) {
		if (list.win == win)
			return list;
		list = list.next;
	}
	return null;
}

void del_task (taskbar * tb, Window win) {
	task* next, prev = null, list = tb.task_list;

	while (list) {
		next = list.next;
		if (list.win == win) {
			/* unlink and free this task */
			tb.num_tasks--;
			if (list.icon_copied) {
				XFreePixmap (dd, list.icon);
				if (list.mask != None)
					XFreePixmap (dd, list.mask);
			}
			if (list.name)
				XFree (list.name);
			free (list);
			if (prev is null)
				tb.task_list = next;
			else
				prev.next = next;
			return;
		}
		prev = list;
		list = next;
	}
}

void taskbar_read_clientlist (taskbar * tb) {
	static int mapped = 1;

	Window* win;
	Window focus_win;
	int num, i, rev, desk, new_desk = 0;
	task* list, next;

	desk = find_desktop (root_win);
	if (desk != tb.my_desktop) {
		new_desk = 1;
		tb.my_desktop = desk;
		// HACK BEGINS
		if(desk >= 5) {
			XUnmapWindow(dd, tb.win);
			mapped = 0;
		} else if(!mapped) {
			XMapWindow(dd, tb.win);
			mapped = 1;
		}
		// HACK ENDS
	}

	XGetInputFocus (dd, &focus_win, &rev);

	/* try unified window spec first */
	win = cast(Window*) get_prop_data (root_win, atom__NET_CLIENT_LIST, XA_WINDOW, &num);
	if (!win)
		return;

	/* remove windows that arn't in the _WIN_CLIENT_LIST anymore */
	list = tb.task_list;
	while (list) {
		list.focused = (focus_win == list.win);
		next = list.next;

		if (!new_desk)
			for (i = num - 1; i >= 0; i--)
				if (list.win == win[i])
					goto dontdel;
		del_task (tb, list.win);
dontdel:

		list = next;
	}

	/* add any new windows */
	for (i = 0; i < num; i++) {
		if (!find_task (tb, win[i]))
			add_task (tb, win[i], (win[i] == focus_win));
	}

	XFree (win);
}

void handle_press (taskbar * tb, int x, int y, int button) {
	auto tk = tb.task_list;
	while (tk) {
		if (x > tk.pos_x && x < tk.pos_x + tk.width) {
			switch(button) {
				default: break;
				case 1:
					if (tk.focused) {
						tk.focused = 0;
						XLowerWindow (dd, tk.win);
					} else {
						tk.focused = 1;
						client_msg(tk.win, atom__NET_ACTIVE_WINDOW, 0, 0, 0, 0, 0);
						XSetInputFocus (dd, tk.win, RevertToNone, CurrentTime);
					}
				break;
				case 2: // middle button
					auto current = tb.task_list;
					task* prev;
					loop: while(current) {
						if(current is tk) {
							if(prev !is null) {
								prev.next = current.next;
								tk.next = tb.task_list;
								tb.task_list = tk;
								gui_draw_taskbar(tb);
							}
							return;
						}
						prev = current;
						current = current.next;
					}
				break;
				case 3: // right button
					client_msg(tk.win, atom__NET_CLOSE_WINDOW, 0, 0, 0, 0, 0);
				break;
				/*
				case 4: // scroll
					if(tk.next != null){
						task* n = tk.next;
						tk.next = n.next;
						n.next = tk.next;
					}
				break;
				case 5: // scroll

				break;
				*/
			}
			gui_sync ();
			gui_draw_task (tb, tk);
		} else {
			if (tk.focused) {
				tk.focused = 0;
				gui_draw_task (tb, tk);
			}
		}

		tk = tk.next;
	}
}

void handle_focusin(taskbar * tb, Window win) {
	auto tk = tb.task_list;
	while (tk) {
		if (tk.focused) {
			if (tk.win != win) {
				tk.focused = 0;
				gui_draw_task (tb, tk);
			}
		} else {
			if (tk.win == win) {
				tk.focused = 1;
				gui_draw_task (tb, tk);
			}
		}
		tk = tk.next;
	}
}

void handle_propertynotify(taskbar * tb, Window win, Atom at){
	if (win == root_win) {
		if (at == atom__NET_CLIENT_LIST || at == atom__NET_CURRENT_DESKTOP) {
			taskbar_read_clientlist (tb);
			gui_draw_taskbar (tb);
		}
		return;
	}

	auto tk = find_task (tb, win);
	if (!tk){
		if (at == atom__NET_WM_STATE && !is_iconified(win)) {
			XWindowAttributes attr;
			XGetWindowAttributes(dd, win, &attr);
			if(attr.map_state == IsViewable) {
				add_task(tb, win, 1);
				gui_draw_taskbar (tb);
			}
		}
/*// I think this is impossible
		else if(at == atom__NET_CURRENT_DESKTOP){
			arch_ulong desk;
			desk = find_desktop(win);
			if(desk == 0xffffffff || desk == tb.my_desktop){
				add_task(tb, win, 1);
				gui_draw_taskbar (tb);
			}
		}
*/
		return;
	}

	if (at == XA_WM_NAME && tk.using_fallback_name) {
		/* window's title changed */
		if (tk.name)
			XFree (tk.name);
		tk.name = cast(char*) get_prop_data (tk.win, XA_WM_NAME, XA_STRING, null);
		gui_draw_task (tb, tk);
	} else if (at == atom_NET_WM_NAME) {
		if (tk.name)
			XFree (tk.name);
		tk.name = cast(char*) get_prop_data (tk.win, atom_NET_WM_NAME, atom_UTF8_STRING, null);
		gui_draw_task (tb, tk);
	} else if (at == atom__NET_WM_STATE) {
		/* iconified state changed? */

		/*

Iconified and not shaded
Shaded changed
Attention changed
Shaded changed
		*/

		auto doNotDelete = false;

		arch_ulong state = get_state(tk.win);

		if(!!(state & STATE_SHADED) != tk.iconified) {
			tk.iconified = !tk.iconified;
			gui_draw_task (tb, tk);
			if(!tk.iconified)
				doNotDelete = true;
			//printf("Shaded changed\n");
		}

		if(!!(state & STATE_DEMANDS_ATTENTION) != tk.demands_attention) {
			tk.demands_attention = !tk.demands_attention;
			gui_draw_task (tb, tk);
			doNotDelete = true;
			//printf("Attention changed\n");
		}

		if((state & STATE_ICONIFIED) && !(state & STATE_SHADED)) {
			if(!doNotDelete) {
				del_task(tb, tk.win);
				gui_draw_taskbar (tb);
			}
			//printf("Iconified and not shaded\n");
		}

	} else if (at == atom__NET_WM_DESKTOP) {
		// Virtual desktop switch
		int desk = find_desktop(tk.win);
		if(desk != 0xffffffff && desk != tb.my_desktop) {
			del_task(tb, tk.win);
			gui_draw_taskbar (tb);
		}
	} else if (at == atom_NET_WM_ICON) {	// Icon update
		get_task_netwmicon (tk);
		gui_draw_task (tb, tk);
	} else if (at == XA_WM_HINTS && tk.using_old_style_icon) {	// Icon update
		// this is obsolete and results in bad looking monochrome icons unnecessarily
		// so we only use if it that's all that was available when initializing the task.

		get_task_hinticon (tk);
		gui_draw_task (tb, tk);
	}
}

extern(C) @nogc nothrow
int handle_error (Display * d, XErrorEvent * ev) {
	// import core.stdc.stdio;
	//printf("%s\n", text);
	return 0;
}

void main() {
	taskbar *tb;
	XEvent ev;
	fd_set fd;
	timeval tv;
	int xfd;
	time_t now;
	tm* lt;

	dd = XOpenDisplay (null);
	if (!dd)
		return;
	scr_screen = DefaultScreen (dd);
	scr_depth = DefaultDepth (dd, scr_screen);
	scr_height = DisplayHeight (dd, scr_screen);
	scr_width = DisplayWidth (dd, scr_screen);
	root_win = RootWindow (dd, scr_screen);

	/* helps us catch windows closing/opening */
	XSelectInput (dd, root_win, EventMask.PropertyChangeMask);

	XSetErrorHandler (&handle_error);

	XInternAtoms (dd, atom_names.ptr, ATOM_COUNT, false, atoms.ptr);

	gui_init ();

	version(WithNotificationArea)
	net_init();

	tb = gui_create_taskbar ();
	xfd = ConnectionNumber (dd);
	gui_sync ();

	int lastSeconds = 0;

	while (1) {
		now = time (null);
		lt = gmtime (&now);
		tv.tv_usec = 0;
		if(lastSeconds > lt.tm_sec)
			tv.tv_sec = 0; // no timeout, we wrapped while processing events
		tv.tv_sec = 60 - lt.tm_sec;
		FD_ZERO (&fd);
		FD_SET (xfd, &fd);
		if (select (xfd + 1, &fd, null, null, &tv) == 0) {
			tb.drawClock();
			lastSeconds = lt.tm_sec;
		}

		while (XPending (dd)) {
			XNextEvent (dd, &ev);
			switch (ev.type) {
				default: break;
				case EventType.ButtonPress:
					handle_press (tb, ev.xbutton.x, ev.xbutton.y, ev.xbutton.button);
				break;
				case EventType.Expose:
					gui_draw_taskbar(tb);
				break;
				case EventType.PropertyNotify:
					handle_propertynotify (tb, ev.xproperty.window, ev.xproperty.atom);
				break;
				case EventType.FocusIn:
					handle_focusin (tb, ev.xfocus.window);
				break;

				case EventType.ReparentNotify:
					if (ev.xany.window == tb.win) /* reparented to us */
						break;
				goto case;
				case EventType.DestroyNotify:
					del_task (tb, ev.xdestroywindow.window);
				goto case;
				case EventType.UnmapNotify:
					version(WithNotificationArea) {
						auto current = icons;
						while(current) {
							if (current.id == ev.xany.window) {
								icon_remove(current);
								break;
							}

							current = current.next;
						}
					}

					gui_draw_taskbar (tb);
				break;

				case EventType.ClientMessage:
					version(WithNotificationArea)
					if (ev.xclient.message_type == net_opcode_atom &&
							ev.xclient.format == 32 &&
							ev.xclient.window == net_sel_win)
						net_message(tb, &ev.xclient);
				break;
			}
		}
	}

	version(WithNotificationArea)
	net_destroy();

	XCloseDisplay (dd);
}
