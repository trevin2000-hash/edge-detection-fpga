clear

%% settings, must match the RTL generics and constants
frame_width     = 1920;   % FRAME_WIDTH_G
frame_height    = 1080;
component_width = 8;    % COMPONENT_WIDTH_C
window_size     = 3;    % WINDOW_SIZE_C

% rbg_to_greyscale: gains in fixed point with component_width fraction bits
gain_frac = [0.2989 0.5870 0.1140];   % RED, GREEN, BLUE_GAIN_FRAC
frac_bits = component_width;

% sobel_filter: mag_o keeps the upper component_width bits of mag_r
acc_width = (component_width + 1) + window_size;   % ACC_WIDTH_C
mag_shift = acc_width - component_width;

%% input image, resized to the test frame size
rgb   = double(imresize(imread("img_1080p.jpg"), [frame_height frame_width]));
red   = rgb(:,:,1);
green = rgb(:,:,2);
blue  = rgb(:,:,3);

%% greyscale, bit-exact with rbg_to_greyscale: gains rounded, result truncated
gains = round(gain_frac * 2^frac_bits);
grey  = floor((red * gains(1) + green * gains(2) + blue * gains(3)) / 2^frac_bits);

%% sobel, bit-exact with sobel_filter
horiz_kernel = [1 0 -1; 2 0 -2; 1 0 -1];   % KERNEL_HORZ_C
vert_kernel  = [1 2 1; 0 0 0; -1 -2 -1];   % KERNEL_VERT_C

% filter2 is correlation: element-wise window times kernel, no kernel flip
gx = filter2(horiz_kernel, grey, 'valid');
gy = filter2(vert_kernel,  grey, 'valid');

% output pixel (x, y) uses the window ending at (x, y); the first
% window_size - 1 rows and columns have no full window and are black
pixel_out = zeros(frame_height, frame_width);
pixel_out(window_size:end, window_size:end) = floor((abs(gx) + abs(gy)) / 2^mag_shift);

%% pack the input as AXI4-Stream video RGB: R high, B middle, G low
pixel_in = red * 2^(2 * component_width) + blue * 2^component_width + green;

%% write the files
write_raster_file("top_level_in_test_vector.txt",  "pixel_in",  pixel_in,  "%9X");
write_raster_file("top_level_out_test_vector.txt", "pixel_out", pixel_out, "%9d");

imshow(uint8(pixel_out), "InitialMagnification", "fit")

function write_raster_file(file_name, value_name, image, value_fmt)
    % one line per pixel in raster order: value, x, y, counting from zero
    [height, width] = size(image);
    [x, y] = meshgrid(0:width-1, 0:height-1);

    % MATLAB stores column by column, so transpose for left to right, top to bottom
    image = image';
    x = x';
    y = y';

    fid = fopen(file_name, "w");
    fprintf(fid, "%9s %5s %5s\n", value_name, "x", "y");
    fprintf(fid, value_fmt + " %5d %5d\n", [image(:) x(:) y(:)]');
    fclose(fid);
end
