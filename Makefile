all:
	dmd taskbar.d ~/arsd/simpledisplay.d ~/arsd/color.d -version=no_phobos imagescale -debug -g
