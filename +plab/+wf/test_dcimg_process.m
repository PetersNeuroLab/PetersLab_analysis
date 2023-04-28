

img_fn = 'D:\AP00400001.dcimg';

dcimg_fid = dcimgmex('open', img_fn);
n_frames = dcimgmex( 'getparam', dcimg_fid, 'NUMBEROF_FRAME' );
im_width = dcimgmex( 'getparam', dcimg_fid, 'IMAGE_WIDTH' );
im_height = dcimgmex( 'getparam', dcimg_fid, 'IMAGE_HEIGHT' );

% Frame number is 0-indexed
curr_im = numFrames;
data = dcimgmex( 'readframe', hdcimg, curr_im-1)';
figure;imagesc(data);axis image;




