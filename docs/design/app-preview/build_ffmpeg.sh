#!/bin/bash
S=/private/tmp/claude-501/-Users-yamadahiroki-myspace-game-collection/792b949b-8dc6-4021-8001-08a2ed00cbe0/scratchpad/preview-video
C=$S/clips; T=$S/tel
dt(){ echo "drawtext=fontfile=$T/font.ttc:textfile=$T/${1}:fontsize=${2}:fontcolor=${3}:x=(w-text_w)/2:y=${4}:enable='between(t,${5},${6})'"; }
BOX1="drawbox=x=0:y=1630:w=iw:h=290:color=black@0.55:t=fill:enable='between(t,0.3,24.9)'"
BOX2="drawbox=x=0:y=1380:w=iw:h=380:color=0xF26B5B@0.92:t=fill:enable='between(t,24.9,29)'"
VF="[0][1][2][3][4][5]concat=n=6:v=1:a=0,$BOX1,$BOX2,$(dt t1a.txt 60 0xFFD54A 1655 0.3 8.9),$(dt t1b.txt 104 white 1735 0.3 8.9),$(dt t2.txt 80 white 1730 8.9 16.9),$(dt t3a.txt 64 white 1655 16.9 24.9),$(dt t3b.txt 110 0xFFD54A 1735 16.9 24.9),$(dt t4a.txt 150 white 1410 24.9 29),$(dt t4b.txt 66 white 1620 24.9 29),format=yuv420p"
ffmpeg -v error -y -i $C/preview-clip-1-homerun.mp4 -i $C/preview-clip-2-othello.mp4 -i $C/preview-clip-3-shogi.mp4 -i $C/preview-clip-4-poker.mp4 -i $C/preview-clip-5-2048.mp4 -i $C/preview-clip-6-runner.mp4 -filter_complex "$VF" -r 30 -c:v libx264 -preset slow -crf 18 -profile:v high -level 4.0 -pix_fmt yuv420p -an -movflags +faststart $S/preview_ffmpeg.mp4 || exit 1
ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,nb_frames -show_entries format=duration,size -of default=nw=1 $S/preview_ffmpeg.mp4
for t in 4 14 18 27; do ffmpeg -v error -y -ss $t -i $S/preview_ffmpeg.mp4 -frames:v 1 -vf scale=300:-1 -update 1 $S/sheets/f_$t.png; done
ffmpeg -v error -y -i $S/sheets/f_4.png -i $S/sheets/f_10.png -i $S/sheets/f_18.png -i $S/sheets/f_27.png -filter_complex hstack=4 -update 1 $S/sheets/ffmpeg_check.png
