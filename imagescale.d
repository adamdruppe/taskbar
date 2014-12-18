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
	{
		auto size = desiredWidth * desiredHeight * bytesPerPixel;
		auto tmpptr = cast(ubyte*) malloc(size);
		if(tmpptr is null)
			throw new Exception("malloc");
		newImage = tmpptr[0 .. size];
		newImage[] = 0;
	}
	scope(exit) free(newImage.ptr);

	// maintain aspect ratio
	if(originalWidth > originalHeight) {
		desiredHeight = originalHeight * desiredWidth / originalWidth;
		assert(desiredWidth > desiredHeight);
	} else if(originalHeight > originalWidth) {
		desiredWidth = originalWidth * desiredHeight / originalHeight;
		assert(desiredHeight > desiredWidth);
	}

	ubyte getOriginalByte(int x, int y, int offset) {
		return data[(y * originalWidth + x) * bytesPerPixel + offset];
	}

	int ix, iy;
	immutable ixstep = originalWidth * 256 / desiredWidth;
	immutable iystep = originalHeight * 256 / desiredHeight;


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
		if(remainderX && ix / 256 + 1 < originalWidth) {
			sum += getOriginalByte(ix / 256 + 1, iy / 256 + 0, offset) * remainderX;
			count += remainderX;
		}
		auto remainderY = iystep % 256;
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
			if(x == desiredWidth) {
				x = 0;
				y++;

				ix = 0;
				iy += iystep;
			}
		}
	}

	// save it back to the original image
	int o = 0;
	int oo = 0;
	foreach(ylol; 0 .. newImageHeight) {
		foreach(b; 0 .. newImageWidth * bytesPerPixel)
			data[b + oo] = newImage[o++];
		oo += originalHeight * bytesPerPixel;
	}
}
