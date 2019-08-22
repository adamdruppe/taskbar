module imagescale;

void downscaleImage(scope ubyte[] data, in int originalWidth, in int originalHeight, int desiredWidth, int desiredHeight, in int bytesPerPixel) {
	assert(data.length == originalHeight * originalWidth * bytesPerPixel);

	if(originalWidth == desiredWidth && originalHeight == desiredHeight)
		return; // no work need be done, we already match the expected params

	assert(originalWidth > desiredWidth);
	assert(originalHeight > desiredHeight);

	import core.stdc.stdlib;
	ubyte[] newImage;
	auto newImageWidth = desiredWidth;
	auto newImageHeight = desiredHeight;

	// maintain aspect ratio
	if(originalWidth > originalHeight) {
		desiredHeight = originalHeight * desiredWidth / originalWidth;
		assert(desiredWidth > desiredHeight);
	} else if(originalHeight > originalWidth) {
		desiredWidth = originalWidth * desiredHeight / originalHeight;
		assert(desiredHeight > desiredWidth);
	}

	import std.stdio; writeln(desiredWidth, "x", desiredHeight);

	{
		auto size = desiredWidth * desiredHeight * bytesPerPixel;
		auto tmpptr = cast(ubyte*) malloc(size);
		if(tmpptr is null)
			throw new Exception("malloc");
		newImage = tmpptr[0 .. size];
		newImage[] = 0;
	}
	scope(exit) free(newImage.ptr);


	ubyte getOriginalByte(long x, long y, int offset) {
		return data[cast(size_t) ((y * originalWidth + x) * bytesPerPixel + offset)];
	}

	long ix, iy;
	immutable ixstep = cast(long) originalWidth * 256 / desiredWidth;
	immutable iystep = cast(long) originalHeight * 256 / desiredHeight;


	int x, y, offset;
	foreach(ref b; newImage) {
		long sum;
		long count;

		// I'm going to average the nearby pixels instead of completely discarding them
		// when we step over them

		foreach(extraY; 0 .. iystep / 256) {
			if(iy / 256 + extraY >= originalHeight)
				break;
			foreach(extraX; 0 .. ixstep / 256) {
				if(ix / 256 + extraX >= originalWidth)
					break;
				sum += getOriginalByte(ix / 256 + extraX, iy / 256 + extraY, offset) * 256L;
				count += 256;
			}
		}

		auto remainderX = ixstep % 256;
		auto remainderY = iystep % 256;
		if(remainderX && ix / 256 + 1 < originalWidth) {
			//import std.stdio; writeln(ix, " ", iy, " ", offset, " ", originalWidth,  " ", originalHeight);
			sum += getOriginalByte(ix / 256 + 1, iy / 256 + 0, offset) * remainderX;
			count += remainderX;
		}
		if(remainderY && iy / 256 + 1 < originalHeight) {
			sum += getOriginalByte(ix / 256 + 0, iy / 256 + 1, offset) * remainderY;
			count += remainderY;
		}

		b = count ? cast(ubyte) ( sum / count ) : 0;

		offset++;
		if(offset == bytesPerPixel) {
			offset = 0;
			x++;

			ix += ixstep;
			if(x >= desiredWidth) {
				x = 0;
				y++;

				ix = 0;
				iy += iystep;

				if(y >= desiredHeight)
					break;
			}
		}
	}

	// save it back to the original image
	int o = 0;
	int oo = ((newImageWidth - desiredWidth) / 2) * bytesPerPixel;
	data[] = 0;
	auto dp = desiredWidth * bytesPerPixel;
	auto op = originalWidth * bytesPerPixel;
	foreach(ylol; 0 .. desiredHeight) {
		data[oo .. oo + dp] = newImage[o .. o + dp];
		o += dp;
		oo += op;
	}
}
