#!/bin/bash
#
# Version:          0.6.3
#
# Licence:          GPL
#
# 2004-05-22        Giacomo Comes <encode2mpeg at users.sourceforge.net>
# 2006-11-06                      <encode2mpeg at email.it>
#
# Purpose:          Convert anything MPlayer can play to AVI/VCD/SVCD/DVD MPEG
#
#   encode2mpeglight.sh is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License.

#   encode2mpeglight.sh is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.

#   You should have received a copy of the GNU General Public License
#   along with encode2mpeglight.sh; if not, write to the Free Software
#   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA


###############################################################################
#   encode2mpeglight.sh is a program that can create VCD/SVCD/DVD MPEGs
#   and eventually extract VobSub subtitles from a DVD using only
#   MEncoder/MPlayer.
#
#   encode2mpeglight.sh is a stripped release of encode2mpeg and therefore the
#   code is redundant in several places, with many variables defined and
#   used for no apparent reason. This cannot be avoided easily.
#   A command line like:
#     encode2mpeglight.sh <encode2mpeglight.sh options>
#   will produce almost the same results as:
#     encode2mpeg -mpeg -mpegonly <encode2mpeglight.sh options>
#
#   If you need more features like:
#     - two or more audio streams, chapters, subtitles, menu
#     - creation, burn and verification of the disk image
#     - creation of MPEG-4 avi and subtitles for a hardware player
#   and more, consider to use the full release (http://encode2mpeg.sf.net)
#
#   encode2mpeglight.sh is mainly tested with the stable release of MPlayer,
#   I try to make it work with SVN too, but due to the "unstable" nature of
#   SVN, bugs may suddenly appear. If you find any, please report them to me.
###############################################################################

###############################################################################
#### start
###############################################################################
export LC_ALL=POSIX
set -B +f
shopt -u xpg_echo nullglob
PROGNAME=${0##*/}
PROGFILE=$(type -p "$0")
VERSION=$(awk '$2=="Version:"{print $3;exit}' <"$PROGFILE")
BROWSER=

###############################################################################
#### some functions
###############################################################################
OptionsText () {
    echo
    echo "Arguments enclosed in [ ] are optional"
}
###############################################################################
ModeText () {
    echo
    echo "$PROGNAME defaults to encode2mpeg's MPEG Mode, the other modes are not"
    echo "available."
}
###############################################################################
usage () {
    echo -e "Usage: $PROGNAME options source\nOptions:"
    sed -n '/^#### PARSING/,/^done/!d;/^done/q;/^[ 	]*-[^)]*)/,/#-/!d;s/)$//;s/) *#/ /;s/#-/# /;s/	*#L.$//;s/#//;p' "$PROGFILE"
    ModeText
    OptionsText
}
###############################################################################
shortusage () {
    echo -e "\n$PROGNAME  v. $VERSION  Copyright (C) 2004-2006 Giacomo Comes\n"
    echo "This is free software; see the source for copying conditions.  There is NO"
    echo "warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE,"
    echo "to the extent permitted by law."
    echo
    echo "Usage: $PROGNAME options source"
    echo "Options:"
    sed -n '/^#### PARSING/,/^done/!d;/^done/q;/^[ 	]*-[^)]*)/!d;s/)$//;s/) *#/ /;s/	*#L.$//;p' "$PROGFILE"
    OptionsText
}
###############################################################################
mp_identify () {
    mplayer -msglevel identify=6 -vo md5sum:outfile=/dev/null -ao null -nocache -frames 0 "$@" 2>/dev/null
}
###############################################################################
id_find () {
    local ID=$1
    shift
    mp_identify "$@" | awk -v id=$ID -F= '$1==id{t=$2}END{print t}'
}
###############################################################################
get_aspect () {
    mplayer -vc -mpegpes, -vo null -ao null -nocache -frames 4 "$@" 2>/dev/null | sed '/^Movie-Aspect is/!d;s/.*Movie-Aspect is //;s/:.*//'
}
###############################################################################
mlistopt () {
    mplayer -list-options 2>&1 | awk '$1=="Name"{m=1}{if(m&&$1!="Name"&&$1!=""&&$1!="Total:")print "\""$1"\""}'
}
###############################################################################
do_log () {
    echo "$1"
    ((LG)) && echo "$1" >>"$output".log || WARN="$WARN${WARN:+\n}$1"
}
###############################################################################
isarg () {
    if [[ ${2:0:1} = - || ! $2 || $2 = help ]]; then
        [[ ${2:0:1} = - ]] && echo "**ERROR: [$PROGNAME] invalid argument '$2' for option '$1'"
        [[ ! $2 ]] && echo "**ERROR: [$PROGNAME] invalid null argument for option '$1'"
        "$PROGFILE" -norc -l | sed '/^        '$1'$/,/^        -/!d' | sed '$d'
        "$PROGFILE" -norc -l | sed '/^        '$1'[ |]/,/^        -/!d' | sed '$d'
        exit 1
    fi
    if [[ $2 = doc ]]; then
        show_html ${3:+$3.html}
        exit
    fi
}
###############################################################################
pr_date () {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')]"
}
###############################################################################
pr_time () {
    date '+%j %H %M %S' | awk '{print $1*86400+$2*3600+$3*60+$4}'
}
###############################################################################
get_abr () {
    local INFO ABR
    INFO=$(mp_identify "${MPLAYEROPT[@]}" ${dvddev:+-dvd-device "$dvddev"} "$@" | grep '^ID_')
    ABR=$(echo "$INFO" | grep '^ID_AUDIO_BITRATE' | tail -1 | cut -f2 -d=)
    case $(echo "$INFO" | grep '^ID_AUDIO_CODEC' | cut -f2 -d=) in
        dvdpcm) abr=$((abr+ABR/1024)) ;;
        *)      abr=$((abr+ABR/1000)) ;;
    esac
}
###############################################################################
get_pwd () {
    pushd &>/dev/null "$1"
    echo "$PWD/$2"
    popd &>/dev/null
}
###############################################################################
show_html () {
    local i LIST HTML PREFIX OPTION INSTDOCDIR SRCDOCDIR
    INSTDOCDIR=${PROGFILE%/bin/$PROGNAME}/share/doc/encode2mpeg
    SRCDOCDIR=${PROGFILE%/$PROGNAME}/doc
    if [[ -f $INSTDOCDIR/encode2mpeg.html ]]; then
        HTML=$(get_pwd "$INSTDOCDIR" encode2mpeg.html)
    elif [[ -f $SRCDOCDIR/encode2mpeg.html ]]; then
        HTML=$(get_pwd "$SRCDOCDIR" encode2mpeg.html)
    else
        HTML="http://encode2mpeg.sourceforge.net"
    fi
    if [[ -f $INSTDOCDIR/html/$1 ]]; then
        HTML=$(get_pwd "$INSTDOCDIR/html" $1)
    elif [[ -f $SRCDOCDIR/html/$1 ]]; then
        HTML=$(get_pwd "$SRCDOCDIR/html" $1)
    elif [[ $1 && ! -d $INSTDOCDIR/html && ! -d $SRCDOCDIR/html ]]; then
        HTML="http://encode2mpeg.sourceforge.net/html/$1"
    fi
    LIST=(mozilla seamonkey firefox)
    [[ ${HTML:0:1} = / ]] && PREFIX=file:// || PREFIX=
    for ((i=0;i<${#LIST[*]};i++)); do
        type ${LIST[i]} &>/dev/null && ${LIST[i]} -remote 'openURL('"$PREFIX$HTML"',new-tab)' 2>/dev/null && return
    done
    LIST=(mozilla firefox seamonkey opera konqueror epiphany galeon)
    if [[ $BROWSER ]]; then
        type "$BROWSER" &>/dev/null && LIST=("$BROWSER") || echo "++ WARN: default browser '$BROWSER' not found, using builtin browser list"
    fi
    for ((i=0;i<${#LIST[*]};i++)); do
        if type "${LIST[i]}" &>/dev/null; then
            case ${LIST[i]} in
                opera) OPTION=--newpage ;;
                epiphany|galeon) OPTION=--new-tab ;;
                *) OPTION= ;;
            esac
            "${LIST[i]}" $OPTION "$HTML" &
            return
        fi
    done
}

###############################################################################
#### variable initialization
###############################################################################
abr=;asr=;vbr=;vfr=;videonorm=;frameformat=;output=;audioformat=;mp1=;mp2=;mp3=;ac3=;dts=;lpcm=;aac=;normalize=;volume=;multiaudio=;mpegchannels=;quiet=;resume=;blank=;encode=;ofps=;mono=;usesbr=;sbr=;clear=;keep=;frames=;avisplit=;channels=;vcustom=;acustom=;cpu=;interlaced=;mpegaspect=;intra_matrix=;inter_matrix=;fixavi=;mpeg=;crop=;audioid=;dvdaudiolang=;bframes=;firstchap=;lastchap=;dvdtrack=;addchapter=;cdi=;mpegfixaspect=;nowait=;vf=;frameres=;trick=;autocrop=;afm=;cache=;removecache=;turbo=;dvddev=;srate=;endpos=;fourcc=;menu=;menubg=;dvdtitle=;rotate=;menuvtsbg=;autosync=;telecine=;AFMT=;telesrc=;vcodec=;vrfyumnt=;burniso=;verify=;fixasync=;removedir=;MPGRES=;GOP=;TXTSUBOPT=;usespeed=;testmca=;chconf=;noodml=;pictsrc=;slideaudio=;audioonly=;norc=;rawsub=;vobsubsrc=;af=;lavf=;subrender=;harddup=;overburn=
unset encsid encsdx encsla addsub addsdx addsla savecache txtsub txtsubopts
zoom=0
scale=1
fast=1
MAXSTEP=6 # burn is the default
step=$MAXSTEP
split=0
vbitrate=16000
mpegmbr=0
overscan=0
iter=0
bakiter=0
hispeed=0
BGTITLE=1
TANIM=0
TFMT=png
TMODE=0
TKFRM=0
TSECS=5
TPART=4
TPARTSEC=15
TFONTSIZE=1
TFONTBG=1
TLINES=2
TCPR=2
MENUERR=0
DVDPLAY=0
MENUOS=0
TSETB=1
DVDFS=1
VTSMBG=0
menufix=0
cdburndevice=0,0,0
dvdburndevice=/dev/cdrecorder
fsize=;fint=;ffrac=;fpre=;audiosize=0
ASPECT=(1 1 4/3 16/9 2.21)
CH6LIST=(l r ls rs c lfe)
TOOL=
MPEG2ENCOPT=;YUVSCALEROPT=;YUVDENOISE=;MPLEXOPT=;VCDIMAGEROPT=;DVDAUTHOROPT=;CDRDAOOPT=;GROWISOFSOPT=;MUSICINOPT=
unset MPLAYEROPT MPLEXSTREAM MENCODEROPT
LPCMPAR=
SUBLANG=
unset SUBTEXT AUDIOTEXT CHAPTERTEXT TITLESET EXTWAV PROFILE MSRC
unset CLEAN
DEBUG=0
LAVC=
WARN=
LOG=
LG=0
SVN=0
MAXFIX=20
timelen=0
ocrsub=0
slidefps=1
default_intra=8,16,19,22,26,27,29,34,16,16,22,24,27,29,34,37,19,22,26,27,29,34,34,38,22,22,26,27,29,34,37,40,22,26,27
default_intra=$default_intra,29,32,35,40,48,26,27,29,32,35,40,48,58,26,27,29,34,38,46,56,69,27,29,35,38,46,56,69,83
default_inter=16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16
default_inter=$default_inter,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,16
hires_intra=8,16,18,20,24,25,26,30,16,16,20,23,25,26,30,30,18,20,22,24,26,28,29,31,20,21,23,24,26,28,31,31,21,23,24
hires_intra=$hires_intra,25,28,30,30,33,23,24,25,28,30,30,33,36,24,25,26,29,29,31,34,38,25,26,28,29,31,34,38,42
hires_inter=$default_inter
kvcd_intra=8,9,12,22,26,27,29,34,9,10,14,26,27,29,34,37,12,14,18,27,29,34,37,38,22,26,27,31,36,37,38,40,26,27,29
kvcd_intra=$kvcd_intra,36,39,38,40,48,27,29,34,37,38,40,48,58,29,34,37,38,40,48,58,69,34,37,38,40,48,58,69,79
kvcd_inter=16,18,20,22,24,26,28,30,18,20,22,24,26,28,30,32,20,22,24,26,28,30,32,34,22,24,26,30,32,32,34,36,24,26
kvcd_inter=$kvcd_inter,28,32,34,34,36,38,26,28,30,32,34,36,38,40,28,30,32,34,36,38,42,42,30,32,34,36,38,40,42,44
tmpgenc_intra=8,16,19,22,26,27,29,34,16,16,22,24,27,29,34,37,19,22,26,27,29,34,34,38,22,22,26,27,29,34,37,40,22,26,27
tmpgenc_intra=$tmpgenc_intra,29,32,35,40,48,26,27,29,32,35,40,40,58,26,27,29,34,38,46,56,69,27,29,35,38,46,56,69,83
tmpgenc_inter=16,17,18,19,20,21,22,23,17,18,19,20,21,22,23,24,18,19,20,21,22,23,24,25,19,20,21,22,23,24,26,27,20,21,22
tmpgenc_inter=$tmpgenc_inter,23,25,26,27,28,21,22,23,24,26,27,28,30,22,23,24,26,27,28,30,31,23,24,25,27,28,30,31,33
TXTSUBDEF=( languageId nolang delay 0 font arial.ttf size 28 bottom-margin 30 characterset ISO8859-1 movie-height-reduction 0 fps default )
AVISUBDEF=( format SubViewer name-extension null fileformat unix version-number off delay 0 fps default suffix default )

#### encode2mpeglight.sh defauls
mpeg=1
encode=7:2:2

(($#)) || ! shortusage || exit 1
CMD=( "$@" )

#### options array
MOPT=( $(mlistopt | grep -v -e : -e '*') 
       $(mlistopt | sed -n '/:/s/:.*/"/p' | uniq) 
       $(mplayer -vfhelp 2>&1 | awk '/vf-/{printf("\"%s\"\n",$1)}') 
       $(mplayer -zrhelp 2>/dev/null | awk '$1~/^-zr/{printf("\"%s\"\n",substr($1,2))}') )

###############################################################################
#### check rc file
###############################################################################
if [[ -s ~/.encode2mpegrc ]]; then
    for ((i=0;i<${#CMD[*]};i++)); do
        [[ ${CMD[i]} = -norc ]] && norc=1 && break
    done
    if [[ ! $norc ]] && ! awk '{if($1~"^#")exit 1}' ~/.encode2mpegrc ; then
        do_log "++ WARN: [$PROGNAME] ~/.encode2mpegrc appears to contain comments, ignoring it" >/dev/null
        norc=1
    fi
    [[ ! $norc ]] && set -- $(<~/.encode2mpegrc) "$@"
fi

###############################################################################
#### arguments parsing
###############################################################################
while (($#)) ; do
#### PARSING
    case $1 in
        -h|-help)
            #-list the available options
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 
            shortusage
            exit
            ;;
        -l|-longhelp)
            #-print this help page
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 
            usage
            exit
            ;;
        -doc|-documentation) #[[<browser>:][<html page>]]
            #-show the html documentation
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 
            [[ ${2%:*} != $2 ]] && BROWSER=${2%:*}
            show_html ${2#*:}
            exit
            ;;
        -noshowlog)
            #-do not show the log file
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 
            quiet=1
            ;;
        -o|-output) #<filename>
            #-filename of the output stream
            echo "$2" | grep -q '/' && [[ ! -d ${2%/*} ]] && echo "**ERROR: [$PROGNAME] directory ${2%/*} argument of '$1' not found" && exit 1
            output=$2
            shift
            ;;
        -a) #<n>
            # aspect ratio     VCD SVCD  DVD
            #     1 -    1:1    x    *    x	x = mpeg2enc and mencoder
            #     2 -    4:3    x    x    x	* = mencoder only
            #     3 -   16:9    x    x    x
            #-    4 -  2.21:1        *    x
            MPEG2ENCOPT="$MPEG2ENCOPT -a $2"
            [[ $2 -eq 0 ]] && MPEG2ENCOPT="${MPEG2ENCOPT% ${2}} 1"
            mpegaspect=$2
            isarg $1 "$2" direct
            shift
            ;;
        -mpegfixaspect) #[pad|crop]
            # force the aspect ratio of the source video to match the one
            # specified with -a; this can be done padding the video with
            #-black lines or cropping the video; the default is padding
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 aspect
            mpegfixaspect=0
            if [[ $2 = pad || $2 = crop ]]; then
                [[ $2 = crop ]] && mpegfixaspect=1
                shift
            fi
            ;;
        -rotate) #<0-3>
            # rotate the source video by 90 degrees; set -mpegfixaspect;
            # 0 rotate clockwise and flip, 1 rotate clockwise
            #-2 rotate counterclockwise, 3 rotate counterclockwise and flip
            rotate=1
            echo "$2" | grep -q '^[0-3]$' && rotate=$2
            isarg $1 "$2" aspect
            shift
            : ${mpegfixaspect:=0}
            ;;
        -overscan) #<n>
            # shrink the video of n% and surround it with black borders,
            # n can be 1-99, using 10 should make visible on a TV the full video
            # image; if n is negative, the result is a magnification of the 
            # central part of the image; n>0 set -mpegfixaspect pad, n<0 set
            #--mpegfixaspect crop; in Avi Mode n can only be positive
            echo "$2" | grep -qE '^-?[0-9]?[0-9]$' && overscan=$2
            [[ ${2:0:1} = - ]] && mpegfixaspect=1 || mpegfixaspect=0
            isarg $1 "${2#-}" $( ((step==1)) && echo Avi || echo aspect)
            shift
            ;;
        -abr) #<n>
            #-audio bit rate of the VCD/SVCD/DVD [MP2:224,MP3:128,AC3:448]
            if [[ $2 = list ]]; then
                sed '/^check_abr/,/case/!d;/'"$audioformat"':/!d;/[^0-9]'"$asr"'/!d;s/[^)]*)//;s/  */ /g;s/^/'"$audioformat $asr"'/' "$PROGFILE"
                exit
            fi
            abr=$2
            isarg $1 "$2" direct
            shift
            ;;
        -asr) #<n>
            #-audio sample rate of the VCD/SVCD/DVD [MP2/MP3:44100,AC3:48000]
            asr=$2
            isarg $1 "$2" direct
            shift
            ;;
        -vbr) #<n>
            #-video bit rate of the VCD/SVCD/DVD [VCD:1152,SVCD:2500,DVD:7500]
            vbr=$2
            isarg $1 "$2" direct
            shift
            ;;
        -vfr) #<n>
            # video frame rate of the output stream
            # [NTSC/VCD:4,NTSC/SVCD-DVD:1,PAL:3,AVI:2]
            #     1 - 24000.0/1001.0 (NTSC 3:2 pulldown converted FILM) 
            #     2 - 24.0 (NATIVE FILM) 
            #     3 - 25.0 (PAL/SECAM VIDEO / converted FILM) 
            #     4 - 30000.0/1001.0 (NTSC VIDEO) 
            #     5 - 30.0
            #     6 - 50.0 (PAL FIELD RATE) 
            #     7 - 60000.0/1001.0 (NTSC FIELD RATE) 
            #-    8 - 60.0
            vfr=$2
            isarg $1 "$2" direct
            shift
            ;;
        -n|-video-norm) #<n|p|s>
            # set the video norm of the VCD/SVCD/DVD; NTSC is USA standard,
            # PAL is European standard and SECAM is French standard; concerning
            #-VCD/SVCD/DVD encoding, SECAM is equivalent to PAL
            case $2 in
                n|N|ntsc|NTSC)   videonorm=n ;;
                p|P|pal|PAL)     videonorm=p ;;
                s|S|secam|SECAM) videonorm=s ;;
                doc|help) isarg $1 $2 direct ;;
                *) echo "**ERROR: [$PROGNAME] invalid argument '$2' for option '$1'" ; "$PROGFILE" -norc $1 help ; exit 1 ;;
            esac
            shift
            ;;
        -p|-pulldown|-telecine) #
            # set a flag in the output stream of the SVCD/DVD that tell the
            # decoder to play the movie as NTSC video using "3:2 pull-down"
            #-instead of "-vfr 4" use "-vfr 1 -p" (smaller output stream) 
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 direct
            telecine=1
            ;;
        -res) #<1-7>
            # force one of the following video resolutios:
            #                      PAL            NTSC
            #		1	352x288		352x240 (VCD) 
            #		2	352x576		352x480 (CVD) 
            #		3	480x576		480x480 (SVCD) 
            #		4	528x576		528x480 (KVCD) 
            #		5	544x576		544x480 (KVCD) 
            #		6	704x576		704x480 (DVB) 
            #-		7	720x576		720x480 (DVD) 
            isarg $1 "$2" direct
            echo "$2" | grep -q '^[1-7]$' && MPGRES=$2
            shift
            ;;
        -gop) #<n>
            # set the number of pictures per GOP; the default value is the one
            #-required by the standard 
            isarg $1 "$2" direct
            GOP=$2
            shift
            ;;
        -kvcd) #<1-4>
            # generate KVCD (www.kvcd.net) compliant frames on output; the
            # following resolutions are possible:
            #		  PAL		  NTSC		GOP
            #	1	528x576		528x480		24
            #	2	528x576		528x480		def
            #	3	544x576		544x480		24
            #-	4	544x576		544x480		def
            isarg $1 "$2" direct
            a=1
            echo "$2" | grep -q '^[1-4]$' && a=$2
            shift 2
            set -- " " -qmatrix kvcd -res $((3+(a+1)/2)) $([[ $a = [13] ]] && echo "-gop 24") "$@"
            ;;
        -vcd) #
            #-generate VCD compliant frames on output (default) 
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 direct
            frameformat=VCD
            ;;
        -svcd) #[1-2]
            # generate SVCD compliant frames on output; the following resolutions
            # are possible:        PAL            NTSC
            #		1	480x576		480x480
            #		2	352x288		352x240
            #-default is 1
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 direct
            frameformat=SVCD
            frameres=1
            echo "$2" | grep -q '^[1-2]$' && frameres=$2 && shift
            ;;
        -svcdht) #
            # enable the VCD header trick; this trick could allow to play SVCD on
            # DVD player that does not support SVCD. For more details see:
            #-http://www.videohelp.com/svcd
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 direct
            trick=1
            ;;
        -dvd) #[1-5]
            # generate DVD compliant frames on output; the following resolutions
            # are possible:        PAL            NTSC
            #		1	720x576		720x480
            #		2	704x576		704x480
            #		3	480x576		480x480 (non standard DVD-SVCD) 
            #		4	352x576		352x480
            #		5	352x288		352x240
            #-default is 1
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 direct
            frameformat=DVD
            frameres=1
            echo "$2" | grep -q '^[1-5]$' && frameres=$2 && shift
            ;;
        -vcodec) #<mpeg1|mpeg2|mpeg4>
            #-force the selected video codec [VCD:mpeg1,SVCD-DVD:mpeg2,AVI:mpeg4]
            isarg $1 "$2" Avi
            [[ $2 = mpeg[124] ]] && vcodec=$2 && [[ ${vcodec:4:1} = [12] ]] && vcodec=${vcodec}video
            shift
            ;;
        -qmatrix) #<kvcd|tmpgenc|default|hi-res>
            # mpeg2enc custom quantization matrices: kvcd produce a smaller
            #-output stream, hi-res is good for hi-quality source material
            case $2 in
                kvcd|tmpgenc|default|hi-res)
                    MPEG2ENCOPT="$MPEG2ENCOPT -K $2"
                    intra_matrix=$(eval echo \$${2/-}_intra)
                    inter_matrix=$(eval echo \$${2/-}_inter)
                    ;;
                *)
                    MPEG2ENCOPT="$MPEG2ENCOPT -K default"
                    intra_matrix=
                    inter_matrix=
                    ;;
            esac
            isarg $1 "$2" direct
            shift
            ;;
        -mpeg1vbr) #
            # produce a VCD/MPEG-1 variable bit rate stream, the output stream
            # is smaller and a complete movie could fit in one VCD; check if
            #-your hardware player support variable bit rate VCD
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 direct
            MPEG2ENCOPT="$MPEG2ENCOPT -q 8"
            LAVC=":vrc_buf_size=327"
            ;;
        -mpegmbr) #<n>
            # set the maximum video bit rate; the default is the value of vbr;
            #-a value of 0 remove the limit
            mpegmbr=$2
            [[ $2 -eq 0 ]] && mpegmbr=
            isarg $1 "$2" mpeg
            shift
            ;;
        -mpegchannels) #<1-6>
            # number of channels of the MPEG audio stream, 1-6 for ac3 and lpcm;
            # 1-2 for mp1, mp2 and mp3; 3-6 for mp2 Multichannel Audio; for the
            #-avi audio stream use MPlayer's option -channels
            mpegchannels=2
            isarg $1 "$2" direct
            echo "$2" | grep -q '^[1-6]$' && mpegchannels=$2
            shift
            ;;
        -normalize)
            #-normalize to the audio stream(s) 
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 $([[ $encode ]] && echo Avi || echo direct)
            normalize=1
            ;;
        -volume) #<n>
            # change amplitude of the audio stream; less than 1.0 decreases,
            #-greater than 1.0 increases (float) 
            volume=$2
            isarg $1 "$2" direct
            shift
            ;;
        -noscale) #
            # encode2mpeg automatically scales the video according to the MPEG
            # profile chosen, this option disables this feature; used mainly
            # for debug purposes.
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 direct
            scale=
            ;;
        -monochrome)
            #-create B/W video or avoid color artifacts in B/W source streams
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 direct
            YUVSCALEROPT="$YUVSCALEROPT -O MONOCHROME"
            ;;
        -split) #<n>
            #-split the resulting MPEG stream in <n> MB chunks.
            split=$2
            isarg $1 "$2" direct
            shift
            ;;
        -encode) #<n:m:i[,b]> 
            # the parameter n:m:i selects the audio codec, video codec options
            # and number of pass for mencoder, possible values are:
            #   n                   m				i
            #   0 copy              0 copy			1 
            #   1 pcm               1 libavcodec/mpeg		2
            #   2 mp3lame/fast      2 as 1 + mbd=2		3
            #   3 mp3lame/standard  3 as 1 + compression opts
            #   4 libavcodec/mp2    4 as 1 + quality opts
            #   5 libavcodec/mp3
            #   6 libavcodec/ac3    for m=[2-4] and i>1 turbo is on
            #   7 toolame/mp2
            #   8 libfaac/aac
            #-  with n=[3-7] b specify the audio bit rate
            encode=5:3:2
            echo "$2" | grep -qE '^[0-8]:[0-4]:[1-9](,[0-9]+)?$' && encode=$2
            isarg $1 "$2" $([[ $mpeg ]] && echo mpeg || echo Avi)
            shift
            ;;
        -telecinesrc) #
            # if you use -encode n:0:i in MPEG Mode, encode2mpeg needs to know
            # if the source NTSC MPEG is telecined, otherwise the stream copy may
            # not work properly; normally encode2mpeg is able to detect telecined
            # sources, but, if the source MPEG is mixed, part not telecined and
            # part telecined, encode2mpeg may fail to detect it. In such case,
            #-you can use this option to specify a telecined source.
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 mpeg
            telesrc=1
            ;;
        -turbo) #<0-1>
            # disable (0) or force (1) turbo mode for the first pass of N pass
            #-encoding (N>1) 
            echo "$2" | grep -q '^[0-1]$' && turbo=$2
            isarg $1 "$2" Avi
            shift
            ;;
        -hispeed) #
            # increase the encoding speed of 25-50% (with -encode n:1:1); the
            # output video stream will be bigger and can have poor quality; this
            # option is mainly intented for testing, but it can be used if you
            #-want to create more quickly an MPEG-4/AVI or a DVD.
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 Avi
            hispeed=1
            ;;
        -bframes) #<0-4>
            # specify the number of B frames; if -encode is n:3:i the default 2,
            #-otherwise the default is no B frames; for VCD the default is 2
            echo "$2" | grep -q '^[0-4]$' && bframes=$2
            isarg $1 "$2" Avi
            shift
            ;;
        -vcustom) #<libavcodec options>
            # specify a custom set of video options for libavcodec, use with
            #--encode n:1:i
            vcustom=$2
            isarg $1 "$2" Avi
            shift
            ;;
        -acustom) #<mp3lame options>
            # specify a custom set of lame options (with -encode 2:m:i) or faac
            #-options (with -encode 8:m:i)
            acustom=$2
            isarg $1 "$2" Avi
            shift
            ;;
        -encsid) #<sid0,sid1,...>
            #-dump the DVD vobsub, sid is the number you give the -sid option
            # of MPlayer.
            encsid=( ${2//,/ } )
            isarg $1 "$2" subtitle
            shift
            ;;
        -encsdx) #<sid0,sid1,...>
            # if you dump subtitle 2 and 4 and you want them to have id 0 and 1
            #-use -encsid 2,4 -encsdx 0,1
            encsdx=( ${2//,/ } )
            isarg $1 "$2" subtitle
            shift
            ;;
        -encsla) #<sla0,sla1,...>
            #-see doc/html/subtitle.html
            encsla=( ${2//,/ } )
            isarg $1 "$2" subtitle
            shift
            ;;
        -usespeed) #
            # do frame rate conversion changing the playback speed; this option
            # can be used if you are converting from NTSC 24fps, with or without
            # telecine, to PAL 25fps and viceversa; during normal frame rate
            # conversion, frames are skipped or duplicated as needed; with this
            #-option all the frames are encoded
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 mpeg
            usespeed=1
            ;;
        -usesbr) #[1-6|>100]
            # use the suggested video bitrate to set the output stream size
            #   1 - for 650MB CD 		4 - for 2 x 650MB CD
            #   2 - for 700MB CD (default) 	5 - for 2 x 700MB CD
            #   3 - for 800MB CD 		6 - for 2 x 800MB CD
            #   n where n > 100 will set the file size to n MB
            #-with -multiaudio you must to set the streamsize in MB
            usesbr=2
            SBR=(650 700 800 "2 x 650" "2 x 700" "2 x 800")
            echo "$2" | grep -q '^[1-6]$' && usesbr=$2 && shift
            echo "$2" | grep -qE '^[1-9][0-9]{2,}$' && usesbr=$2 && shift
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 Avi
            ;;
        -cpu) #<n>
            #-number of cpu to use, default all the cpu present in the system
            cpu=1
            echo "$2" | grep -q '^[1-8]$' && cpu=$2
            isarg $1 "$2" Avi
            shift
            ;;
        -interlaced)
            #-turn on optimization for interlaced source video. 
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 $([[ $mpeg ]] && echo mpeg || echo Avi)
            interlaced=1
            ;;
        -slidefps) #<n>
            # fps to use when creating video from pictures, default is 1; if
            # there is a audio file associated with a picture, the duration of
            #-the audio file is used
            isarg $1 "$2" images
            slidefps=$(awk -v a=$2 'BEGIN{printf("%.3f",1/a)}')
            shift
            ;;
        -slideaudio) #<audio file>
            # use the content of <audio file> as audio stream when creating video
            #-from pictures; it works correctly only if used with mf://singlepic
            slideaudio=$2
            if [[ ! -f $2 && $2 != /dev/null ]]; then
                [[ $2 = doc || $2 = help || ! $2 ]] && isarg $1 "$2" images || ! echo "**ERROR: [$PROGNAME] slide audio file '$2' not found" || exit 1
            fi
            shift
            ;;
        -norc)
            #-do not use the settings in the file $HOME/.encode2mpegrc
            [[ $2 = doc || $2 = help ]] && isarg $1 $2 rc
            ;;
        -debug)
            # make a more verbose log file and creates a debug file; if you are
            # submitting a bug report, use this option and compress and send the
            #-log file and the debug file
            [[ $2 = doc || $2 = help ]] && isarg $1 $2
            echo "$2" | grep -q '^[0-7]$' && DEBUG=$2 && shift || DEBUG=3
            ;;
        (-frames)
            frames=$2
            isarg $1 $2
            shift
            ;;
        (-channels)
            channels=$2
            isarg $1 $2
            shift
            ;;
        (-srate)
            MPLAYEROPT=( "${MPLAYEROPT[@]}" -srate $2 -af-adv force=1 )
            srate=$2
            isarg $1 $2
            shift
            ;;
        (-endpos)
            endpos=$2
            isarg $1 $2
            shift
            ;;
        (-hr-edl-seek)
            MENCODEROPT=( "${MENCODEROPT[@]}" $1 )
            ;;
        (-vf)
            vf="-vf $2"
            MPLAYEROPT=( "${MPLAYEROPT[@]}" $vf )
            isarg $1 $2
            shift
            ;;
        (-af)
            af="-af $2"
            isarg $1 $2
            shift
            ;;
        (-dvd-device)
            dvddev=$2
            isarg $1 $2
            shift
            ;;
        (mf://*)
            MPLAYEROPT[${#MPLAYEROPT[*]}]=$1
            pictsrc=1
            a=$IFS
            IFS=,
            PICTSRC=( ${1#mf://} )
            IFS=$a
            srate=48000
            ;;
        (-sub)
            [[ ! -f $2 ]] && echo "**ERROR: [$PROGNAME] subtitle file '$2' not found" && exit 1
            MPLAYEROPT=( "${MPLAYEROPT[@]}" $1 "$2" )
            subrender=1
            shift
            ;;
        (-mpeg|-mpegonly|-nosplit) ;;
        *)
            if [[ ! $TOOL ]]; then
                [[ ${1:0:1} = - ]] && ! echo "${MOPT[@]}" | grep -q "\"${1#-}\"" && \
                  echo -e "Unknown option $1\nIf this is a valid MPlayer option add '-toolopts mplayer' in front of it" && exit 1
                MPLAYEROPT[${#MPLAYEROPT[*]}]=$1
            else
                case $TOOL in
                    *)
                        MPLAYEROPT[${#MPLAYEROPT[*]}]=$1
                        ;;
                esac
            fi
            ;;
    esac
    shift
done

[[ -s ~/.encode2mpegrc && ! $norc ]] && do_log "   INFO: [$PROGNAME] using .encode2mpegrc settings: '$(<~/.encode2mpegrc)'"
if [[ $subrender || $harddup ]]; then
    if [[ $vf ]]; then
        vf=$vf${subrender:+,expand=::::1}
        [[ $harddup ]] && ! echo $vf | grep -q harddup && vf=$vf,harddup
        for ((a=0;a<${#MPLAYEROPT[*]};a++)); do
            [[ ${MPLAYEROPT[a]} = -vf ]] && MPLAYEROPT[a+1]=${vf#-vf }
        done
    else
        vf="-vf ${subrender:+expand=::::1}${harddup:+${subrender:+,}harddup}"
        MPLAYEROPT=( "${MPLAYEROPT[@]}" $vf )
    fi
fi

###############################################################################
#### debug part
###############################################################################
if ((DEBUG)); then
    if ((DEBUG & 1)); then
        #### redirect stdout and stderr to the debug file
    exec 3>&1
    rm -f "$output".debug.fifo
    mkfifo "$output".debug.fifo
    tee "$output".debug <"$output".debug.fifo >&3 &
    PROCTEE=$!
    exec &>"$output".debug.fifo
        trap 'rm "$output".debug.fifo' 0
    fi
    if ((DEBUG & 2)); then
        #### catch mplayer/mencoder errors
        mplayer () {
            command mplayer "$@"
            ret=$? ; (( ret )) && error_line "$FUNCNAME $*" || true
        }
        mencoder () {
            command mencoder "$@"
            ret=$? ; (( ret )) && error_line "$FUNCNAME $*" || true
        }
    fi
    ((DEBUG & 4)) && set -x
fi

###############################################################################
#### ERROR if some options conflict is detected part 1/2
###############################################################################
#### mplayer/mencoder
for a in mplayer mencoder ; do
    type -f $a &>/dev/null || ! echo "**ERROR: [$PROGNAME] $a missing, install $(echo ${a:0:2} | tr '[:lower:]' '[:upper:]')${a:2}" || exit 1
done
#### output stream name check
[[ ! $output ]] && echo "**ERROR: [$PROGNAME] name of the output stream missing (-o name)" && exit 1
#### unspecified video norm
[[ ! $videonorm && step -gt 1 && ! ( $mpeg && ${encode%,*} = ?:0:? && ! $menu ) && ${#TITLESET[*]} -eq 0 ]] && \
  echo "**ERROR: [$PROGNAME] you must specify a video norm (-n n|p|s)" && exit 1
#### libfaac check
if [[ ${encode%,*} = 8:?:? ]]; then
    ! mencoder -oac help 2>/dev/null | grep -q faac && echo "**ERROR: [$PROGNAME] missing libfaac support in mencoder [-encode 8:m:i]" && exit 1
fi
#### mpeg4
if [[ $vcodec = mpeg4 ]]; then
    [[ $pictsrc && $step -gt 1 && $mpeg ]] && echo "**ERROR: [$PROGNAME] -vcodec mpeg4, -mpeg and mf://file are not compatible" && exit 1
fi
#### pictsrc
if [[ $pictsrc ]]; then
    [[ $slideaudio != /dev/null && ${encode%,*} = 0:?:? && $mpeg ]] && \
      echo "**ERROR: [$PROGNAME] -encode 0:m:i is not compatible with mf:// in MPEG Mode" && exit 1
    [[ $audioonly ]] && echo "**ERROR: [$PROGNAME] -audioonly does not work with mf://" && exit 1
fi
#### -encode 1:m:i is not allowed
[[ ${encode%,*} = 1:?:? ]] && echo "**ERROR: [$PROGNAME] do not use -encode 1:m:i" && exit 1

###############################################################################
#### WARN if some options conflict is detected
###############################################################################
#### missing toolame support
if [[ ${encode%,*} = 7:?:? ]]; then
    if ! mencoder -oac help 2>/dev/null | grep -q t[wo]olame ; then
        encode=4:${encode#?:}
        do_log "++ WARN: [$PROGNAME] missing toolame support in mencoder, setting -encode $encode"
    else
        mencoder -oac help 2>/dev/null | grep -q toolame && TOOLAME=toolame || TOOLAME=twolame
    fi
fi

###############################################################################
#### set default values for unspecified parameters
###############################################################################
if [[ ! $multiaudio ]]; then
    audiostream=1
fi
###############################################################################
if [[ $encode ]]; then
    case ${encode%%:*} in
        0) [[ ! $pictsrc ]] && 
               AFMT=acopy ;;
        2|3|5) AFMT=mp3 ;;
        4|7)   AFMT=mp2 ;;
        6)     AFMT=ac3 ;;
        8)     AFMT=aac ;;
    esac
    [[ $AFMT ]] && eval : ${audioformat:-\${$AFMT:=copy\}}
fi
: ${frameformat:=VCD}
: ${audioformat:=${AFMT:-mp2}}
: ${mp1:=mp2enc}
((${mpegchannels:-2}>2)) && : ${mp2:=musicin} || : ${mp2:=mp2enc}
: ${mp3:=lame}
: ${ac3:=mencoder}
: ${dts:=copy}
: ${aac:=faac}
case $audioformat in
    mp1)
        case ${mpegchannels:-2} in
            1) : ${abr:=192} ;;
            2) : ${abr:=384} ;;
        esac
        ;;
    mp2)
        case ${mpegchannels:-2} in
            1) : ${abr:=112} ;;
            2) : ${abr:=224} ;;
            [3-6]) : ${abr:=384} ;;
        esac
        ;;
    mp3)
        case ${mpegchannels:-2} in
            1) : ${abr:=64} ;;
            2) : ${abr:=128} ;;
        esac
        ;;
    ac3)
        case ${mpegchannels:-2} in
            1) : ${abr:=96} ;;
            2) : ${abr:=192} ;;
            3) : ${abr:=320} ;; # to verify
            4) : ${abr:=384} ;; # to verify
            5) : ${abr:=448} ;; # to verify
            6) : ${abr:=448} ;;
        esac
        ;;
    aac) : ${abr:=$((${mpegchannels:-2}*48))} ;;
    #### mplex fails with asr != 48000 for lpcm
    lpcm) : ${asr:=48000} ${abr:=$((asr*16*${mpegchannels:-2}/1024))} ;;
esac
if [[ ${encode%,*} = 0:?:? && ${!audioformat} = copy ]]; then
    abr=0
    if [[ ! $multiaudio ]]; then
        get_abr
    fi
fi
[[ $mpeg && ${encode%,*} = ?:0:? ]] && \
  vbr=$(($(id_find ID_VIDEO_BITRATE "${MPLAYEROPT[@]}" ${dvddev:+-dvd-device "$dvddev"} "$@")/1000))
case $frameformat in
    DVD) : ${asr:=48000} ;;
    *)   : ${asr:=44100} ;;
esac
case $videonorm in
    p|s)
        : ${vfr:=3}
        ;;
    n)
        [[ $frameformat != VCD && ! $vfr && $hispeed -eq 0 && ! $testmca ]] && vfr=1 && telecine=1
        : ${vfr:=4}
        ;;
esac
[[ $encode && ${encode%,*} != ?:0:? ]] && : ${vfr:=2}
if [[ ! $ofps ]]; then
    case $vfr in
        1) ofps=24000/1001 ;;
        2) ofps=24 ;;
        3) ofps=25 ;;
        4) ofps=30000/1001 ;;
        5) ofps=30 ;;
        6) ofps=50 ;;
        7) ofps=60000/1001 ;;
        8) ofps=60 ;;
    esac
fi
if [[ $split && $split -eq 0 ]]; then
    [[ $mpeg ]] && split= || split=800
fi

###############################################################################
#### get MPlayer version
###############################################################################
mver=$(mencoder 2>/dev/null | awk '$1=="MEncoder"{print $2;exit}')

###############################################################################
#### threads check
###############################################################################
if [[ ! $cpu && -f /proc/cpuinfo ]]; then
    cpu=$(grep -c ^processor /proc/cpuinfo)
    #### if there are 2 logical cpu but 1 physical (hyperthreading)
    #### use only one thread. With kernel 2.4.x it is more efficent.
    ((cpu==2)) && [[ $(uname -r | cut -f 1-2 -d .) = 2.4 ]] && \
      [[ $(grep ^siblings /proc/cpuinfo | uniq | wc -l) -eq 1 ]] && \
      cpu=$((cpu/$(grep ^siblings /proc/cpuinfo | uniq | awk 'END{print $NF}')))
fi
((cpu<2)) && cpu=

###############################################################################
#### -ao pcm arguments
###############################################################################
PCMWAV=(pcm:waveheader:fast:file=%$((${#output}+4))%"$output".wav)
PCMTMP=(pcm:waveheader:fast:file=%$((${#output}+4))%"$output".tmp)
PCMNOWYUV=(pcm:nowaveheader:fast:file=/dev/fd/4)

[[ $dvddev ]] && MPLAYEROPT=( "${MPLAYEROPT[@]}" -dvd-device "$dvddev" )

###############################################################################
#### mplayer/mencoder/mjpegtools options
###############################################################################

#### mencoder output suffix
if [[ $encode ]]; then
    [[ $mpeg ]] && SUF=mpeg || SUF=avi
fi

#### MPLAYERINFO is used for [info]
MPLAYERINFO=( "${MPLAYEROPT[@]}" )

#### mf:// case
if [[ $pictsrc ]]; then
    if [[ $slideaudio && $slideaudio != /dev/null ]]; then
        [[ $(id_find ID_AUDIO_RATE "$slideaudio") != $asr ]] && SRATE="-srate $asr -af-adv force=1" || SRATE=
        CLEAN[${#CLEAN[*]}]="$output".wav
        mplayer "$slideaudio" $SRATE -vo null -vc dummy -ao "${PCMWAV[@]}" $afm ${mpegchannels:+-channels $mpegchannels -af channels=$mpegchannels}
        MPLAYEROPT=( "${MPLAYEROPT[@]}" -fps 1/$(id_find ID_LENGTH "$output".wav) -audiofile "$output".wav )
    else
        if [[ $slideaudio = /dev/null ]]; then
            MPLAYEROPT=( "${MPLAYEROPT[@]}" -fps $slidefps )
            encode=0:${encode#?:}
        else
            MPLAYEROPT=( "${MPLAYEROPT[@]}" -fps $slidefps -audiofile /dev/zero -audio-demuxer 20 -rawaudio format=0x1:rate=48000 )
        fi
    fi
fi

#### MENCODERARG is used for mencoding, vobsub dumping
MENCODERARG=( "${MPLAYEROPT[@]}" ${frames:+-frames $frames} )

MENCODERARG=( "${MENCODERARG[@]}" "${MENCODEROPT[@]}" ${endpos:+-endpos $endpos} ${ofps:+-ofps $ofps} )
if [[ $mpeg && $mpegchannels ]]; then
    MENCODERARG=( "${MENCODERARG[@]}" -channels $mpegchannels )
    af=$(echo "${af:--af }${af:+,}" | sed 's/channels=[^,]*,//')channels=$mpegchannels
elif [[ $channels ]]; then
    MENCODERARG=( "${MENCODERARG[@]}" -channels $channels )
    af=$(echo "${af:--af }${af:+,}" | sed 's/channels=[^,]*,//')channels=$channels
fi

YUVSCALEROPT="-v 1 -n $videonorm ${scale:+-O $frameformat} $YUVSCALEROPT"

MPEG2ENCOPT="${cpu:+-M $cpu }-v 1 -S ${split:-50000} -n $videonorm -F $vfr -s -r 16 ${telecine:+-p} $MPEG2ENCOPT"
case $vfr in
    1|2) MPEG2ENCOPT="-g 6 -G ${GOP:-12} $MPEG2ENCOPT" ;;
    3|6) MPEG2ENCOPT="-g 6 -G ${GOP:-15} $MPEG2ENCOPT" ;;
    4|5|7|8) MPEG2ENCOPT="-g 9 -G ${GOP:-18} $MPEG2ENCOPT" ;;
esac
[[ $frameformat = VCD ]] && MPEG2ENCOPT="-R 2 $MPEG2ENCOPT"
echo "$MPEG2ENCOPT" | grep -q -e '-K hi-res' && YUVSCALEROPT="-M BICUBIC $YUVSCALEROPT" && \
  MPEG2ENCOPT="-4 1 -2 1 $MPEG2ENCOPT" || MPEG2ENCOPT="-4 2 -2 1 $MPEG2ENCOPT"

case $frameformat in
    VCD) MPGRES=${MPGRES:-1} ;;
    SVCD)
        case $frameres in
            1) MPGRES=${MPGRES:-3} ;;
            2) MPGRES=${MPGRES:-1} ;;
        esac
        ;;
    DVD)
        case $frameres in
            1) MPGRES=${MPGRES:-7} ;;
            2) MPGRES=${MPGRES:-6} ;;
            3) MPGRES=${MPGRES:-3} ;;
            4) MPGRES=${MPGRES:-2} ;;
            5) MPGRES=${MPGRES:-1} ;;
        esac
        ;;
esac
case $MPGRES in
    1) H_RES=352 ; [[ $videonorm = n ]] && V_RES=240 || V_RES=288 ;;
    2) H_RES=352 ; [[ $videonorm = n ]] && V_RES=480 || V_RES=576 ;;
    3) H_RES=480 ; [[ $videonorm = n ]] && V_RES=480 || V_RES=576 ;;
    4) H_RES=528 ; [[ $videonorm = n ]] && V_RES=480 || V_RES=576 ;;
    5) H_RES=544 ; [[ $videonorm = n ]] && V_RES=480 || V_RES=576 ;;
    6) H_RES=704 ; [[ $videonorm = n ]] && V_RES=480 || V_RES=576 ;;
    7) H_RES=720 ; [[ $videonorm = n ]] && V_RES=480 || V_RES=576 ;;
esac
case $frameformat in
    VCD)
        : ${vbr:=1152}
        MPEG2ENCOPT="-f 2 -b $vbr -V 46 -B $(((abr*audiostream*101875-vbr*2819+3980000)/100000)) $MPEG2ENCOPT"
        MPLEXOPT="-f 2 -V -b 46 -r $(((abr*audiostream+vbr)*4)) $MPLEXOPT"
        VCDIMAGEROPT="-t vcd2 $VCDIMAGEROPT"
        H_STILL=704
        [[ $videonorm = n ]] && V_STILL=480 || V_STILL=576
        ((MPGRES!=1)) && YUVSCALEROPT="-O SIZE_${H_RES}x${V_RES} ${YUVSCALEROPT/ -O $frameformat}"
        MAXBR=1394
        ;;
    SVCD)
        : ${vbr:=2500}
        MPEG2ENCOPT="-f 5 -b $vbr -V 113 -B $(((abr*audiostream*101250+vbr*742+1665400)/100000)) $MPEG2ENCOPT"
        MPLEXOPT="-V -b 113 -r $(((abr*audiostream+vbr)*4)) $MPLEXOPT"
        if [[ $trick ]]; then
            MPLEXOPT="-f 2 $MPLEXOPT"
            VCDIMAGEROPT="-t vcd2 $VCDIMAGEROPT"
        else
            MPLEXOPT="-f 5 $MPLEXOPT"
            VCDIMAGEROPT="-t svcd $VCDIMAGEROPT"
        fi
        H_STILL=704
        [[ $videonorm = n ]] && V_STILL=480 || V_STILL=576
        ((frameres>1||MPGRES!=3)) && YUVSCALEROPT="-O SIZE_${H_RES}x${V_RES} ${YUVSCALEROPT/ -O $frameformat}"
        MAXBR=2778
        ;;
    DVD)
        : ${vbr:=7500}
        MPEG2ENCOPT="-f 8 -b $vbr -V 230 -B $(((abr*audiostream*101250+vbr*742+1665400)/100000)) $MPEG2ENCOPT"
        MPLEXOPT="-f 8 -V -b 230 -r $(((abr*audiostream+vbr)*4)) $MPLEXOPT"
        H_STILL=720
        [[ $videonorm = n ]] && V_STILL=480 || V_STILL=576
        ((frameres>1||MPGRES!=7)) && YUVSCALEROPT="-O SIZE_${H_RES}x${V_RES} ${YUVSCALEROPT/ -O $frameformat}"
        MAXBR=10080
        ;;
esac

###############################################################################
#### mencoder audio/video/pass options
###############################################################################
if [[ $encode ]]; then
    OPTIONS="-noskiplimit -sws $((hispeed?1:7))"
    if [[ $mpeg ]]; then
        # mencoder can put in the MPEG container:
        # video: mpeg1, mpeg2, mpeg4
        # audio: mp1, mp2, mp3, ac3, aac (not yet: lpcm, dts)
        [[ ${encode%,*} != ?:0:? ]] && : ${mpegaspect:=2}
        #MUX="-mpegopts ${mpegaspect:+vaspect=${ASPECT[mpegaspect]}:}:vbitrate=${vbr}"
        MUX="-mpegopts "
        if [[ $telecine ]]; then
            if [[ $vcodec = mpeg2video || ! $vcodec && $frameformat != VCD ]]; then
                if [[ $vfr = [12] ]]; then
                    [[ $videonorm = n ]] && MUX2=":telecine" || MUX2=":film2pal"
                else
                    do_log "++ WARN: [$PROGNAME] telecine only works with 24000/1001 or 24 fps, disabling it"
                fi
            else
                do_log "++ WARN: [$PROGNAME] telecine only works for MPEG-2, disabling it"
            fi
        fi
        case $frameformat in
            VCD)  MUX="${MUX}format=xvcd"  LAVC="vcodec=${vcodec:-mpeg1video}${LAVC:-:vrc_buf_size=327:vrc_minrate=${vbr}:vrc_maxrate=${vbr}}" ;;
            SVCD) if [[ $trick ]]; then MUX="${MUX}format=xvcd" ; else 
                  MUX="${MUX}format=xsvcd" ; fi ; LAVC="vcodec=${vcodec:-mpeg2video}:vrc_buf_size=917" ;;
            DVD)  MUX="${MUX}format=dvd"   LAVC="vcodec=${vcodec:-mpeg2video}:vrc_buf_size=1835" ;;
        esac
        case $vfr in
            1|2) LAVC="$LAVC:keyint=$((hispeed?1:${GOP:-12}))" ;;
            3|6) LAVC="$LAVC:keyint=$((hispeed?1:${GOP:-15}))" ;;
            4|5|7|8) LAVC="$LAVC:keyint=$((hispeed?1:${GOP:-18}))" ;;
        esac
        [[ $frameformat = VCD && ! $bframes ]] && LAVC="$LAVC:vmax_b_frames=2"
        [[ $mpegmbr ]] && [[ $mpegmbr -lt $vbr ]] && mpegmbr=$vbr
        #### -a 1 is SAR=1 (do not scale), not DAR=1
        [[ $mpegaspect != 1 ]] && LAVC="${LAVC}:aspect=${ASPECT[mpegaspect]}"
        LAVC="${LAVC}${mpegmbr:+:vrc_maxrate=$mpegmbr}${inter_matrix:+:inter_matrix=${inter_matrix}}${intra_matrix:+:intra_matrix=${intra_matrix}}"
        OF="-of mpeg"
        NOSKIP=-noskip
        vbitrate=$vbr
        if [[ ${encode%,*} != ?:0:? ]]; then
            for ((a=0;a<${#MENCODERARG[*]};a++)); do
                while [[ ${MENCODERARG[a]} = -vf ]]; do
                    unset MENCODERARG[a] MENCODERARG[a+1]
                    MENCODERARG=( "${MENCODERARG[@]}" )
                done
            done
            MENCODERARG=( "${MENCODERARG[@]}" ${vf:--vf }${vf:+,}${scale:+scale=${H_RES}:${V_RES}${interlaced:+:1},}harddup )
        fi
    fi

    BASIC="$LAVC:vbitrate=${vbitrate}${cpu:+:threads=$cpu}${bframes:+:vmax_b_frames=$bframes}"
    ((hispeed)) && BASIC="$BASIC:vme=0" || BASIC="$BASIC:psnr"
    [[ $mpeg && $frameformat = VCD ]] || BASIC="$BASIC${interlaced:+:ildct:ilme}"
    echo "$YUVSCALEROPT" | grep -q -e '-O MONOCHROME' && BASIC="$BASIC:gray"
    
    HQ="${BASIC}:mbd=2"

    if [[ $mpeg ]]; then
        #### dia=6 could be added
        BESTSIZE="${BASIC}:mbd=1:loop:mv0:vlelim=-4:vcelim=7:trell:precmp=1:cmp=1:subcmp=1"
        [[ ! $bframes ]] && BESTSIZE="$BESTSIZE:vmax_b_frames=2"

        #### last_pred=1-2 could be added
        BESTQUALITY="${BASIC}:mbd=2:mv0:precmp=6:cmp=6:subcmp=6"
        [[ $vbitrate -ge 3500 && $frameformat != VCD && $vcodec != mpeg1video ]] && BESTQUALITY="$BESTQUALITY:dc=9"
    fi

    case $encode in
        0:?:?|0:?:?,*) AUDIOPASS="-oac copy" ;;
        1:?:?|1:?:?,*) AUDIOPASS="-oac pcm" ;;
        2:?:?|2:?:?,*) AUDIOPASS="-oac mp3lame -lameopts ${acustom:-fast}" ;;
        3:?:?) AUDIOPASS="-oac mp3lame -lameopts preset=standard" ;;
        4:?:?) AUDIOPASS="-oac lavc -lavcopts acodec=mp2:abitrate=$abr" ;;
        5:?:?) AUDIOPASS="-oac lavc -lavcopts acodec=mp3:abitrate=$abr" ;;
        6:?:?) AUDIOPASS="-oac lavc -lavcopts acodec=ac3:abitrate=$abr" ;;
        7:?:?) AUDIOPASS="-oac $TOOLAME -${TOOLAME}opts br=$abr" ;;
        8:?:?) AUDIOPASS="-oac faac -faacopts ${acustom:-br=$abr}" ;;
        3:?:?,*) AUDIOPASS="-oac mp3lame -lameopts preset=${encode#*,}" ;;
        4:?:?,*) AUDIOPASS="-oac lavc -lavcopts acodec=mp2:abitrate=${encode#*,}" ;;
        5:?:?,*) AUDIOPASS="-oac lavc -lavcopts acodec=mp3:abitrate=${encode#*,}" ;;
        6:?:?,*) AUDIOPASS="-oac lavc -lavcopts acodec=ac3:abitrate=${encode#*,}" ;;
        7:?:?,*) AUDIOPASS="-oac $TOOLAME -${TOOLAME}opts br=${encode#*,}" ;;
        8:?:?,*) AUDIOPASS="-oac faac -faacopts ${acustom:-br=${encode#*,}}" ;;
    esac
    encode=${encode%,*}
    case $encode in
        ?:0:?) VIDEOPASS="$OF $MUX -ovc copy $NOSKIP" ; encode=${encode%%:*}:0:1 ; turbo=0 ;; # copy uses only one pass
        ?:1:?) VIDEOPASS="$OF $MUX$MUX2 -ovc lavc -lavcopts ${BASIC}${vcustom:+:$vcustom}" ; : ${turbo:=0} ;;
        ?:2:?) VIDEOPASS="$OF $MUX$MUX2 -ovc lavc -lavcopts ${HQ}"                         ; : ${turbo:=1} ;;
        ?:3:?) VIDEOPASS="$OF $MUX$MUX2 -ovc lavc -lavcopts ${BESTSIZE}"                   ; : ${turbo:=1} ;;
        ?:4:?) VIDEOPASS="$OF $MUX$MUX2 -ovc lavc -lavcopts ${BESTQUALITY}"                ; : ${turbo:=1} ;;
    esac
    ((turbo)) && turbo=:turbo || turbo=
    PASS=${encode##*:}
    [[ $normalize && $encode != 0:?:? ]] && af=${af:--af }${af:+,}volnorm
fi


###############################################################################
#### more functions
###############################################################################
status_bit () {
    local a
    case $1 in
        avi) bit=0 ;;
        mpv) bit=1 ;;
        mpa) bit=2 ;;
        mpg) bit=3 ;;
        img) bit=4 ;;
        sub) bit=5 ;;
        ach) bit=6 ;;
        fno) bit=7 ;;
        ch0) bit=8 ;;
        sbm) bit=9 ;;
        spl) bit=10 ;;
    esac
    if [[ $2 = set ]]; then
        skip=$((skip|1<<bit))
    else
        return $(((skip&1<<bit) && 1))
    fi
}
###############################################################################
file_size () { #fsize,fint,ffrac,fpre
    local -a PRE=([1]=K M G T)
    local i=0
    fsize=$(ls -l "$1" | awk '{print $5}')
    fint=$fsize
    ffrac=0
    while ((fint>=1024)) ; do
        ((fint/1024 < 1024)) && ffrac=$((( fint+=51 )%1024))
        i=$((++i))
        fint=$((fint/1024))
    done
    ffrac=$((ffrac*10/1024))
    fpre=${PRE[i]}
}
###############################################################################
show_file_info () {
    file_size "$2"
    echo "   $1: $2 is $fsize bytes, $fint.$ffrac ${fpre}B" >>"$output".log
}
###############################################################################
show_finalvideo_info () {
    local codec TYPE i VIDEO OUT ASPECT CH FAAC SUBST
    SUBST=
    VIDEO="$(mplayer -nocache -frames 0 -vo null -nosound "$2" 2>/dev/null | grep "^VIDEO:")"
    if [[ ! $VIDEO ]]; then
        # MPEGs with MPEG-4 video do not show all the video informations in one line,
        # assebmling the informations (kbps is missing):
        OUT="$(mplayer -nocache -frames 1 -vo null -nosound -v "$2" 2>/dev/null)"
        if echo "$OUT" | grep -q '^\[V].*fourcc:0x10000004' ; then
            VIDEO="VIDEO:  MPEG-4  $(echo "$OUT" | awk '$1=="VO:"&&$2=="[null]"{print $3}')"
            ASPECT=$(echo "$OUT" | awk '$1=="Movie-Aspect"{print $3}')
            case $ASPECT in
                undefined) VIDEO="$VIDEO  (aspect 1)" ;;
                1.33:1) VIDEO="$VIDEO  (aspect 2)" ;;
                1.78:1) VIDEO="$VIDEO  (aspect 3)" ;;
                2.21:1) VIDEO="$VIDEO  (aspect 4)" ;;
                *) VIDEO="$VIDEO  (aspect $ASPECT)" ;;
            esac
            VIDEO="$VIDEO  $(echo "$OUT" | awk '$1=="[V]"{print $5}')"
        fi
    fi
    echo "   $1: $VIDEO" >>"$output".log
    #### removed -vc dummy
    for i in $(mplayer -vo null -ao null -nocache -frames 1 -v "$2" 2>/dev/null | awk '/==> Found audio str/{print $NF}' | sort -n) ; do
        echo -n "   $1: AUDIO[$i]: " >>"$output".log
        codec=$(mplayer -ac mp3, -nocache -frames 0 -v -ao null -vo null "$2" -aid $i 2>/dev/null | \
          sed '/Selected audio codec:/!d;s/[^(]*(//;s/).*//;s/AAC.*/& AAC/;s/.* //')
        #### AAC info are insufficient/incorrect
        if [[ $codec = AAC ]]; then
            CH=$(mplayer -nocache -frames 0 -v -ao null -vo null "$2" -aid $i 2>/dev/null | awk '/FAAD: Negotiated samplerate:/{print $NF}')
            if type &>/dev/null faad ; then
                mplayer -dumpaudio -dumpfile "$output".audio -aid $i "$2" 2>/dev/null
                FAAC=$(faad -i "$output".audio 2>&1 | tail -2 | head -n 1)
                #ADTS, 4.087 sec, 103 kbps, 44100 Hz
                rm -f "$output".audio
                SUBST="s/AAC.*/AAC:$(echo "$FAAC" | sed 's/.*,\([^,]*Hz\).*/\1/'), "
                SUBST="${SUBST}$CH ch, $(echo "$FAAC" | sed 's/,.*//'),"
                SUBST="${SUBST}$(echo "$FAAC" | sed 's/.*,\([^,]*kbps\).*/\1/')"
                SUBST="${SUBST}/;"
            else
                SUBST="s/2 ch,/$CH ch,/;"
            fi
        fi
        mplayer -ac mp3, -nocache -frames 0 -v -ao null -vo null "$2" -aid $i 2>/dev/null | sed '/^Opening audio decode/,/^AUDIO:/!d;s/\r//g' | \
          grep -e '^AC3:' -e '^MPEG' -e '^AUDIO:' | sed 's/AUDIO/'"$codec"'/;'"$SUBST"'q' >>"$output".log
    done
    TYPE=$1
    shift
    for i ; do
        show_file_info "$TYPE" "$i"
    done
}
###############################################################################
video_duration () {
    mencoder "$@" -ovc copy -nosound -o /dev/null -quiet 2>&1 | awk '/^Video stream:/{print $10+$10/$12}'
}
###############################################################################
job_exit () {
    EXIT=$?
        status_bit mpg || [[ ! -f ${output}.mpg && ! -f ${output}01.mpg ]] || show_finalvideo_info  "MPEG" "${output}"*.mpg
        [[ $usesbr ]] && ((DEBUG && usesbr>6)) && awk -v u=$usesbr -v f=$fsize \
          'BEGIN{b=u*1024*1024;printf("--DEBUG: [usesbr] target: %dMB (%d bytes), error: %f%%\n",u,b,(b-f)*100/b)}' >>"$output".log
    sec=$(($(pr_time)-STARTTIME))
    echo " JOBEND: $output $(pr_date) ($((sec/3600))h$((sec/60%60))m$((sec%60))s)" >>"$output".log
    rm -f "${CLEAN[@]}" psnr_??????.log
    ((DEBUG)) && exec >&1- >&2- && exec >&3
    if [[ -f $output.yuvscaler.log || -f $output.mpeg2enc.log ]]; then
        echo
    else
        ((!EXIT)) && [[ ! $quiet ]] && cat "$output".log
    fi
    ((DEBUG)) && rm -f "$output".debug.fifo && kill $PROCTEE
}
###############################################################################
me_log () {
    rm -f "$output".fifo
    mkfifo "$output".fifo
    tee -a /dev/stderr <"$output".fifo | sed 's/.*\r//' | \
      awk '/^PSNR:|^M[EP][ln]|^There are |^\[open]|^audio stream:|^number of|^subtitle|^==> |^Recommended video bitrate/{sub(/^/,"   INFO: [mencoder] ");
        print}' >>"$output".log &
}
###############################################################################
me_bit_log () {
    rm -f "$output".fifo
    mkfifo "$output".fifo
    tee -a /dev/stderr <"$output".fifo | sed 's/.*\r//;/^Recommended video bitrate/!d;s/^/   INFO: [mencoder] /' >>"$output".log &
}
###############################################################################
check_abr () {
        # abr permitted:
        # ac3: ( 8000/11025/12000)  8 16 24 32 40 48 56 64 80 96 112 128 144 160
        # ac3: (16000/22050/24000)    16 24 32 40 48 56 64 80 96 112 128     160     192 224 256 288 320
        # ac3: (32000/44100/48000)          32 40 48 56 64 80 96 112 128     160     192 224 256     320     384     448 512 576 640
        # mp3: ( 8000/11025/12000)  8 16 24 32 40 48 56 64 80 96 112 128 144 160
        # mp3: (16000/22050/24000)  8 16 24 32 40 48 56 64 80 96 112 128 144 160
        # mp3: (32000/44100/48000)          32 40 48 56 64 80 96 112 128     160     192 224 256     320
        # mp2: ( 8000/11025/12000)
        # mp2: (16000/22050/24000)  8 16 24 32 40 48 56 64 80 96 112 128 144 160
        # mp2: (32000/44100/48000)          32    48 56 64 80 96 112 128     160     192 224 256     320     384
        # mp1: ( 8000/11025/12000)
        # mp1: (16000/22050/24000)          32    48 56 64 80 96 112 128 144 160 176 192 224 256
        # mp1: (32000/44100/48000)          32          64    96     128     160     192 224 256 288 320 352 384 416 448
    case $1 in
        ac3)
            case $2 in
                8000|11025|12000)
                    case $3 in
                        8|16|24|32|40|48|56|64|80|96|112|128|144|160) : ;;
                        *) return 1 ;;
                    esac
                    ;;
                16000|22050|24000)
                    case $3 in
                        16|24|32|40|48|56|64|80|96|112|128|160|192|224|256|288|320) : ;;
                        *) return 1 ;;
                    esac
                    ;;
                32000|44100|48000)
                    case $3 in
                        32|40|48|56|64|80|96|112|128|160|192|224|256|320|384|448|512|576|640) : ;;
                        *) return 1 ;;
                    esac
                    ;;
                *) return 1 ;;
            esac
            ;;
        mp3)
            case $2 in
                8000|11025|12000|16000|22050|24000)
                    case $3 in
                        8|16|24|32|40|48|56|64|80|96|112|128|144|160) : ;;
                        *) return 1 ;;
                    esac
                    ;;
                32000|44100|48000)
                    case $3 in
                        32|40|48|56|64|80|96|112|128|160|192|224|256|320) : ;;
                        *) return 1 ;;
                    esac
                    ;;
                *) return 1 ;;
            esac
            ;;
        mp2)
            case $2 in
                16000|22050|24000)
                    case $3 in
                        8|16|24|32|40|48|56|64|80|96|112|128|144|160) : ;;
                        *) return 1 ;;
                    esac
                    ;;
                32000|44100|48000)
                    case $3 in
                        32|48|56|64|80|96|112|128|160|192|224|256|320|384) : ;;
                        *) return 1 ;;
                    esac
                    ;;
                *) return 1 ;;
            esac
            ;;
        mp1)
            case $2 in
                16000|22050|24000)
                    case $3 in
                        32|48|56|64|80|96|112|128|144|160|176|192|224|256) : ;;
                        *) return 1 ;;
                    esac
                    ;;
                32000|44100|48000)
                    case $3 in
                        32|64|96|128|160|192|224|256|288|320|352|384|416|448) : ;;
                        *) return 1 ;;
                    esac
                    ;;
                *) return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}
###############################################################################
debug_line () {
    echo "--DEBUG: [$PROGNAME] $2($1) $(eval echo $(sed -n $1p "$PROGFILE" | sed 's/ |.*//;s/.>.*//;s/</\\\</'))" >>"$output".log
}
###############################################################################
error_line () {
    echo "--DEBUG: [$PROGNAME] $1"
    echo "**ERROR: [$PROGNAME] there has been an error during the execution of the previous line, this should not happen"
    echo "possible causes:"
    echo "  0) missing or misspelled input stream"
    echo "  1) the input stream is corrupted"
    echo "       -> try a different input stream"
    echo "  2) one of the options used has triggered a bug present only on your combination of architecture/compiler/distribution"
    echo "       -> try to recompile MPlayer with a different compiler version or try another distribution"
    if ((SVN)); then
        echo "  3) one of the options used is not valid or is buggy for your SVN/unsupported version of MPlayer/MEncoder"
        echo "       -> check MPlayer's man page and/or try a supported release of MPlayer"
    fi
    echo
    echo "submit a bugreport if you think this is a bug in $PROGNAME"
    exit $ret
}
###############################################################################
check_mencoder_abr () {
    local codec lib ASR
    codec=([4]=mp2 mp3 ac3 mp2 aac)
    lib=([4]=libavcodec libavcodec libavcodec lib${TOOLAME} libfaac)
    ASR=${encode%%:*}
    check_abr ${codec[ASR]} $1 $2 || ! echo "**ERROR: [$PROGNAME] ${lib[ASR]} does not support $2 kbps / $1 Hz for ${codec[ASR]}" || exit 1
}
###############################################################################
is_film2pal () {
    local a
    a=$(mplayer -nocache "$@" -vo null -nosound -benchmark -frames 60 -noquiet 2>/dev/null | tr '\015' '\012' | tail | \
      awk -F/ '$1~/^V:/{s=$1;t=$2}END{match(s,/ [0-9]+$/);n=substr(s,RSTART+1);match(t,/[0-9]+ /);m=substr(t,1,RLENGTH-1);r=n/m;if(r>1.02)print "24"}')
    [[ $a ]] && a=$(mplayer -nocache "$@" -vo null -nosound -benchmark -frames 1500 -noquiet 2>/dev/null | tr '\015' '\012' | tail | \
      awk -F/ '$1~/^V:/{s=$1;t=$2}END{match(s,/ [0-9]+$/);n=substr(s,RSTART+1);match(t,/[0-9]+ /);m=substr(t,1,RLENGTH-1);r=n/m;
      if(r>1.042)print "24000/1001fps";if(r<1.042&&r>1.041)print "24fps"}')
    echo "$a"
}

###############################################################################
#### ERROR if some options conflict is detected part 2/2
###############################################################################
#### libavcodec codec/asr/abr
#### libtoolame asr/abr
#### libmp3lame asr
#### no check is done on the other channel in case of multiaudio
if [[ $encode = [2-8]:?:? ]]; then
    if [[ $srate ]]; then
        r=$srate
    else
        r=$(id_find ID_AUDIO_RATE "${MPLAYERINFO[@]}")
        if [[ ! $r ]]; then
            do_log "++ WARN: [$PROGNAME] failure to detect the audio sample rate of the input stream"
            [[ ! $multiaudio && ! $audioid ]] && do_log "++ WARN: [$PROGNAME] if your source video does not have audio use -encode 0:${encode#*:}" || \
              do_log "++ WARN: [$PROGNAME] probably is incorrect the audio stream selected with -${audioid:+aid}${multiaudio:+multiaudio}"
        fi
        if [[ $mpeg && ! $usespeed ]]; then
            case $frameformat in
                *VCD) ((r != 44100)) && do_log "++ WARN: [$PROGNAME] $frameformat standard requires 44100kHz audio, add -srate 44100" ;;
                DVD)  ((r != 48000)) && do_log "++ WARN: [$PROGNAME] $frameformat standard requires 48000kHz audio, add -srate 48000" ;;
            esac
        fi
    fi
    if [[ $encode = [4-7]:?:? ]]; then
        check_mencoder_abr "$r" ${AUDIOPASS##*=}
    elif [[ $encode = 8:?:? ]]; then
        case $r in
            8000|11025|12000|16000|22050|24000|32000|44100|48000|64000|88200|96000) : ;;
            *) echo "**ERROR: [$PROGNAME] libfaac does not support $r Hz sample rate" ; exit 1 ;;
        esac
    else
        case $r in
            8000|11025|12000|16000|22050|24000|32000|44100|48000) : ;;
            *) echo "**ERROR: [$PROGNAME] libmp3lame does not support $r Hz sample rate" ; exit 1 ;;
        esac
    fi
fi
#### copy of non-MPEG audio in a VCD
if [[ $step -gt 1 && $frameformat = VCD && $encode = 0:?:? && ( $mpeg || ${!audioformat} = copy ) && ! $testmca && ! $pictsrc ]]; then
    a=$(id_find ID_AUDIO_CODEC "${MPLAYERINFO[@]}")
    [[ $a != mp3 ]] && echo "**ERROR: [$PROGNAME] you cannot copy $a audio in a $frameformat" && exit 1
fi
#### mpegchannels > 2 only with ac3 and aac
[[ $mpeg && ${mpegchannels:-2} -gt 2 && $encode = [2-57]:?:? ]] && CODEC=([2]=mp3 mp3 mp2 mp3 [7]=mp2) && \
  echo "**ERROR: [$PROGNAME] audio codec ${CODEC[${encode%%:*}]} selected with -encode $encode do not support more than 2 audio channels" && exit 1
###############################################################################
#### set cleanup
###############################################################################
trap 'job_exit' 0
CLEAN[${#CLEAN[*]}]="$output".fifo

skip=0
LG=1

###############################################################################
#### start the log file
###############################################################################
if [[ ! $resume ]] ; then
    { if [[ $LOG ]]; then
          echo "$LOG"
      else
          STARTTIME=$(pr_time)
          echo "### LOG: $output $(pr_date)" 
      fi
      echo -n "   INFO: [$PROGNAME] version $VERSION running in "
      if ((${#TITLESET[*]})); then
          echo -n "Titleset Mode"
      else
          if [[ $mpeg ]]; then
              [[ $testmca ]] && echo -n "Testmca Mode" || echo -n "MPEG Mode"
          fi
      fi
      echo "${cpu:+ (cpu=$cpu)}"
      echo "   INFO: [$PROGNAME] command line: '${CMD[@]}'"
    } >"$output".log
fi

###############################################################################
#### WARNING if some requested tools are missing and can be replaced
###############################################################################
#### WARN
if [[ $WARN ]]; then
    echo -e "$WARN" >>"$output".log
fi
#### volume and audio copy
if [[ $volume ]]; then
    [[ $encode = 0:?:? && ( ${!audioformat} = copy || $step -eq 1 || $mpeg ) || ${!audioformat} = copy && ! $encode ]] && \
      do_log "++ WARN: [$PROGNAME] you cannot modify the volume of the output audio stream if you are making a copy the input audio stream"
fi
#### cpu and bframes
if [[ $cpu && $bframes ]]; then
    ((bframes)) && do_log "++ WARN: [$PROGNAME] with bframes>0 the encoding will be faster with cpu=1"
fi
#### -usespeed
if [[ $usespeed && ( $encode = 0:?:? || $encode = ?:0:? ) ]]; then 
    do_log "++ WARN: [$PROGNAME] -usespeed may not work if you do not encode both audio and video." && echo -n "Press return to proceed" && read
fi
#### total br
[[ $encode != ?:0:? ]] && ((step>1&&abr*audiostream*1024/1000+vbr>MAXBR)) && \
  do_log "++ WARN: [$PROGNAME] total video+audio bitrate ($vbr+$((abr*audiostream*1024/1000))kbps) exceed $frameformat specifications (${MAXBR}kbps)"
#### -slideaudio/single picture
if [[ $slideaudio && $slideaudio != /dev/null && $pictsrc ]]; then
    ((${#PICTSRC[*]}!=1||$(ls ${PICTSRC[0]} | wc -l)!=1)) && \
      do_log "++ WARN: [$PROGNAME] you should use only one source image if you use the option -slideaudio"
fi

###############################################################################
#### dump some info in the log file
###############################################################################
{ VARS=(frameformat ${split:+split} vfr vbr abr asr ${mpegchannels:+mpegchannels} ${GOP:+GOP} audioformat) # audioformat must be the last
  VARS[${#VARS[*]}]=${!VARS[${#VARS[*]}-1]}
  [[ $volume && ! $encode ]] && VARS[${#VARS[*]}]=volume
  echo -n "   MPEG: "
  for ((i=0;i<${#VARS[*]};i++)) ; do
      echo -n "${VARS[i]}:${!VARS[i]} "
  done
  echo -n "${multiaudio:+multiaudio:${multiaudio// /,} }"
  echo -n "mpegencoder:$([ $mpeg ] && echo mencoder || echo mpeg2enc)"
  [[ $mpegaspect ]] && echo -n " aspect:${ASPECT[mpegaspect]}"
  [[ $cdi && $frameformat = VCD ]] && echo -n " CD-i"
  [[ $telecine ]] && echo -n " telecine"
  echo
  VARS=(encode ${vcodec:+vcodec} ${volume:+volume} ${usesbr:+usesbr} ${avisplit:+avisplit} ${channels:+channels} AUDIOPASS VIDEOPASS PASS)
  if [[ $encode ]]; then
      echo -n "   $([ $mpeg ] && echo MPEG || echo \ AVI): "
      for ((i=0;i<${#VARS[*]};i++)) ; do
          echo -n "${VARS[i]}:${!VARS[i]} "
      done
      if ((PASS>1)); then
          [[ $turbo ]] && echo -n "TURBO:on " || echo -n "TURBO:off "
      fi
      txt=
      [[ $(echo $encode | cut -f 2 -d:) = 1 && $vcustom ]] && txt="libavcodec"
      [[ ${encode%%:*} = 2 && $acustom ]] && txt=${txt:+${txt} and} && txt="$txt lame"
      txt=${txt:+(custom ${txt} options)}
      echo $txt
  fi
  [[ ! $resume ]] && { [[ $audioonly ]] && mp_identify "$audioonly" || mp_identify "${MPLAYERINFO[@]}" -frames 1 ; } | \
    sed -n '/^ID_/s/^/   INFO: [identify] /p' | uniq
  VARS=(${encode:+MENCODERARG} MPLAYERYUVOPT)
  VARS=(${encode:+MENCODERARG})
  for ((i=0;i<${#VARS[*]};i++)) ; do
      s="INFO: \[${VARS[i]}] \${${VARS[i]}[*]}"
      eval echo "\ \ \ $s"
  done
} >>"$output".log
h_res=$(grep ID_VIDEO_WIDTH "$output".log | tail -1 | cut -f2 -d=)
v_res=$(grep ID_VIDEO_HEIGHT "$output".log | tail -1 | cut -f2 -d=)
if [[ $pictsrc ]]; then
    v_res=$(mplayer -vo null "${MPLAYERINFO[@]}" -frames 1 2>/dev/null | awk '/^VO:/{print $3}' | head -n 1)
    h_res=${v_res%x*}
    v_res=${v_res#*x}
fi
[[ $mpeg && ${encode%,*} = ?:0:? ]] && H_RES=$h_res && V_RES=$v_res

###############################################################################
#### put the volume in DB
###############################################################################
if [[ $volume ]]; then
    volume=$(awk -v a=$volume 'BEGIN{if(a>0) print 20*log(a)/log(10) ; else print 0}')
    af=${af:--af }${af:+,}volume=$volume
fi

[[ ${mver:0:5} = 1.0rc ]] || SVN=1

###############################################################################
#### telecined (NTSC/PAL) MPEG copy/speed encoding change
###############################################################################
if [[ $mpeg && ( $encode = ?:0:? || $usespeed ) || $usespeed && ! $encode && $step -gt 1 ]]; then
    FPS=($(grep ID_VIDEO_FPS "$output".log | cut -f2 -d=) [1]=23.976 24.000 25.000 29.970 30.000 50.000 59.940 60.000)
    for ((i=1;i<9;i++)); do
        a=$(awk -v a=${FPS[0]} -v b=${FPS[i]} 'BEGIN{if (sqrt((a-b)*(a-b))<.02) print b}')
        if [[ $a ]]; then
            if [[ ${FPS[0]} != ${FPS[i]} ]]; then
                do_log "++ WARN: [$PROGNAME] input video frame rate is not exactly ${FPS[i]}fps"
                FPS[0]=${FPS[i]}
            fi
            FPS[10]=$i
            break
        fi
    done
    [[ $usespeed && $i -eq 9 ]] && do_log "++ WARN: [$PROGNAME] input video frame rate is not a valid NTSC/PAL value; disabling -usespeed" && usespeed=
    
    if [[ ${FPS[0]} = ${FPS[4]} || ${FPS[0]} = ${FPS[5]} ]]; then
        FPS[9]=$(mplayer -nocache -quiet "${MPLAYERINFO[@]}" -vo null -nosound -benchmark -frames 60 2>/dev/null | awk '/^demux_mpg:/{print $2}')
        [[ ${FPS[9]} = 24fps || ${FPS[9]} = 24000/1001fps ]] && FPS[10]=$((FPS[10]-3))
    elif [[ ${FPS[0]} = ${FPS[3]} ]]; then
        FPS[9]=$(is_film2pal "${MPLAYERINFO[@]}")
        if [[ ${FPS[9]} ]]; then
            [[ ${FPS[9]} = 24fps ]] && FPS[10]=2 || FPS[10]=1
        fi
    fi
    if [[ $usespeed ]]; then
        if ((vfr!=${FPS[10]})); then
            NSPEEDCOEF=([1]=1001 1001 5 1001 1001 5 1001 25 1250 5 25 2500 5 1200 6 2 2400 12 1001 1001 2 1001 5 2000 2 1200 6 1001 )
            MSPEEDCOEF=([1]=1000  960 4  800  480 2  400 24 1001 4 12 1001 2 1001 5 1 1001  5 1000  200 1  500 3 1001 1 1001 5 1000 )
            DCOEF=([1]=-2 3 7 10 12 13 13)
            if ((vfr>${FPS[10]})); then
                #### black magic here ;-)
                n=$((vfr+${FPS[10]}+${DCOEF[${FPS[10]}]}))
                a=${NSPEEDCOEF[n]}/${MSPEEDCOEF[n]}
            else
                n=$((vfr+${FPS[10]}+${DCOEF[vfr]}))
                a=${MSPEEDCOEF[n]}/${NSPEEDCOEF[n]}
            fi
            MENCODERARG=( -speed $a -srate $asr -af-adv force=1 "${MENCODERARG[@]}" )
            MPLAYERYUVOPT=("${MPLAYERYUVOPT[@]}" -speed $a )
            do_log "   INFO: [usespeed] using speed factor $a"
        fi
    elif [[ ${FPS[0]} = ${FPS[4]} || ${FPS[0]} = ${FPS[5]} || ${FPS[0]} = ${FPS[3]} ]]; then
        if [[ ${FPS[9]} = 24fps || ${FPS[9]} = 24000/1001fps || $telesrc ]]; then
            { echo -n "   INFO: [$PROGNAME] "
              [[ ${FPS[9]} = 24fps || ${FPS[9]} = 24000/1001fps ]] && echo -n "detected" || echo -n "user selected"
              [[ ${FPS[0]} = ${FPS[3]} ]] && echo -n " PAL" || echo -n " NTSC"
              echo " telecined source" 
            } | tee -a "$output".log
            [[ ${FPS[10]} = 1 ]] && MENCODERARG=( "${MENCODERARG[@]}" -ofps 24000/1001 -mc 0 ) || MENCODERARG=( "${MENCODERARG[@]}" -ofps 24 -mc 0 )
        fi
    fi
fi

###############################################################################
#### scale and expand/crop to adapt the aspect ratio
#### added rotation and overscan
###############################################################################
if [[ $mpegfixaspect && $step -gt 1 ]]; then
    a=$(get_aspect "${MPLAYERINFO[@]}")
    [[ ${a:0:9} = undefined ]] && a=$(awk -v a=$h_res -v b=$v_res 'BEGIN{printf("%f",a/b)}')
    [[ $mpegaspect = 1 ]] && b=$(awk -v a=$H_RES -v b=$V_RES 'BEGIN{printf("%f",a/b)}') || b=${ASPECT[${mpegaspect:-2}]}
    vfilter=$(awk -v a=$a -v A=$b -v W=$H_RES -v H=$V_RES -v crop=$mpegfixaspect -v i=${interlaced:-0} -v r=$rotate -v o=$overscan -v logfile="$(echo "$output" | sed 's/\\/\\\\/g')".log 'BEGIN{
      ko=(1-o/100)
      if(a==1.78||a==1.74)a=16/9
      if(a==1.33||a==1.30)a=4/3
      if(A=="4/3")A=4/3
      if(A=="16/9")A=16/9
      if(r!=""){
        A=1/A
        tmp=W
        W=H
        H=tmp
      }
      if(a>A&&crop==0||a<A&&crop==1){
        Eh=A*H/a
        Ew=W
      }else{
        Ew=W*a/A
        Eh=H
      }
      Ew=2*int(Ew*ko/2+0.50)
      Eh=2*int(Eh*ko/2+0.50)
      printf("-vf scale=%d:%d",Ew,Eh)
      printf("   INFO: [mpegfixaspect] -vf scale=%d:%d",Ew,Eh) >>logfile
      if(i==1)printf(":1")
      if(i==1)printf(":1") >>logfile
      if(crop==0){
        printf(",expand=%d:%d",W,H)
        printf(",expand=%d:%d",W,H) >>logfile
      }else{
        printf(",crop=%d:%d",W,H)
        printf(",crop=%d:%d",W,H) >>logfile
      }
      if(r!=""){
        printf(",rotate=%d",r)
        printf(",rotate=%d",r) >>logfile
      }
      if(o!=0) printf(" [overscan=%d]",o) >>logfile
      printf("\n") >>logfile
    }')
    if [[ $mpeg ]]; then
        for ((a=0;a<${#MENCODERARG[*]};a++)); do
            if [[ ${MENCODERARG[a]} = -vf ]]; then
                MENCODERARG[a+1]=$(echo ${MENCODERARG[a+1]} | sed 's/scale=[^,]*,//;s/^/'"${vfilter#-vf }"',/')
            fi
        done
    fi
fi

###############################################################################
#### warn for aspect ratio
###############################################################################
if [[ ( $mpeg && $encode != ?:0:? || ! $mpeg && $step -gt 1 ) && ! $mpegfixaspect && ${#TITLESET[*]} -eq 0 && ! $testmca ]]; then
    a=$(get_aspect "${MPLAYERINFO[@]}")
    [[ ${mpegaspect:-2} = 2 && $a != 1.33 && $a != 1.30 || ${mpegaspect:-2} = 3 && $a != 1.78 && $a != 1.74 || ${mpegaspect:-2} = 4 && $a != 2.21 ]] && \
      do_log "++ WARN: [$PROGNAME] selected aspect ratio [${ASPECT[${mpegaspect:-2}]}] and source aspect ratio [$a] are different"
fi

###############################################################################
#### dvd vobsub
###############################################################################
#### function to select the vobsub to extract
next_vobsub_idx () {
    if ((${#SID[*]})); then
        if ((idx < ${#encsid[*]})); then
            SID=(-sid ${encsid[idx]} -vobsuboutindex ${encsdx[idx]} ${encsla:+-vobsuboutid ${encsla[idx]}} -vobsubout "$output")
            do_log "   INFO: [$PROGNAME] dumping subtitle ${encsid[idx]} to vobsub ${encsdx[idx]}${encsla:+ (${encsla[idx]})}"
            idx=$((idx+1))
        else
            unset SID
        fi
    fi
}
#### turn on vobsub extraction if encsid is given
if (( ${#encsid[*]} )) ; then
    (( ${#encsdx[*]} )) || encsdx=( ${encsid[*]} )
    idx=0
    SID=(0000)
    next_vobsub_idx
else
    unset SID
fi
status_bit sub || unset SID

###############################################################################
#### test condition "extra"
###############################################################################
IDACOD=$(grep "ID_AUDIO_CODEC" "$output".log | tail -1 | cut -f2 -d=)
[[ $IDACOD = hwdts ]] && echo "**ERROR: [$PROGNAME] dts audio support missing in MPlayer" && \
  echo "**ERROR: add dts support (libdts-0.0.2.tar.gz) or select a non dts stream" && \
  echo "**ERROR: example:  -aid 128 (ac3), -aid 160 (lpcm), -aid 0 (mpeg)" && exit 1
[[ $mpeg && ! $pictsrc && ( $encode = 1:?:? || $multiaudio || $encode = 0:?:? && $IDACOD != mp3 && $IDACOD != a52 && $IDACOD != faad ) ]] && extra=1 || \
  extra=
[[ $extra ]] && do_log "**ERROR: [$PROGNAME] output stream: unsupported audio codec $IDACOD" && exit 1

CLEAN[${#CLEAN[*]}]="$output".tmp

###############################################################################
#### AVI/MPEG section
###############################################################################
if [[ $encode ]]; then
    if status_bit avi ; then
        find_sbr () {
            local kv k ka
            sleep 2
            [[ $mpeg ]] && kv=9888 k=33 ka=1015 || kv=10000 k=0 ka=1011
            if ((usesbr<=6)); then
                sbr=$(awk '/for '"${SBR[usesbr-1]}"'MB CD/{print $NF}' <"$output".log)
                [[ $sbr ]] && ((sbr<vbitrate)) && VIDEOPASS=${VIDEOPASS/vbitrate=$vbitrate:/vbitrate=$sbr:} && \
                  do_log "   INFO: [mencoder] using vbitrate=$sbr"
            else
                #### usesbr is in MB
                #### remind: 650-800,650-1400,800-1400
                sbr[0]=650
                sbr[1]=1400
                sbr[2]=$(awk '/for '"${SBR[0]}"'MB CD/{print $NF}' <"$output".log)
                sbr[3]=$(awk '/for '"${SBR[4]}"'MB CD/{print $NF}' <"$output".log)
                [[ ${sbr[2]} && ${sbr[3]} ]] && \
                  sbr[4]=$(((((usesbr*kv/10000-k)-(audiosize*ka/1000))*(sbr[3]-sbr[2])+sbr[1]*sbr[2]-sbr[0]*sbr[3])/(sbr[1]-sbr[0])))
                [[ ${sbr[4]} ]] && ((sbr[4]<vbitrate && sbr[4]>0)) && VIDEOPASS=${VIDEOPASS/vbitrate=$vbitrate:/vbitrate=${sbr[4]}:} && \
                  do_log "   INFO: [mencoder] using vbitrate=${sbr[4]}"
            fi
        }
        AID=
        if [[ ! $extra ]]; then
            RAWVIDEO=( -o "$output".$SUF )
        fi
        #### start mencoder
        PLOG=( -passlogfile "$output".avi2pass.log )
        MSG=( -msglevel open=6:demuxer=6:demux=6 )
        rm -f frameno.avi
        [[ $encode = 0:?:? && ! $extra ]] && F= || F=$af
            if [[ $usesbr && ! $extra ]]; then
            ((DEBUG)) && debug_line $((LINENO+2)) "usesbr "
            me_bit_log
            mencoder         $OPTIONS -ovc frameno         -o /dev/null       "${SID[@]}" "${MENCODERARG[@]}" $AID $AUDIOPASS $F       &>"$output".fifo
                find_sbr
                next_vobsub_idx
            fi
        if ((PASS==1)); then
            ((DEBUG)) && debug_line $((LINENO+2)) "PASS 1/$PASS"
            me_log
            mencoder         $OPTIONS $VIDEOPASS           "${RAWVIDEO[@]}"   "${SID[@]}" "${MENCODERARG[@]}" $AID $AUDIOPASS $F "${MSG[@]}" >"$output".fifo
            next_vobsub_idx
        else
            #### N pass
            CLEAN[${#CLEAN[*]}]="$output".avi2pass.log
            ((DEBUG)) && debug_line $((LINENO+1)) "PASS 1/$PASS"
            mencoder         $OPTIONS ${VIDEOPASS}:vpass=1$turbo -o /dev/null "${SID[@]}" "${MENCODERARG[@]}" $AID $AUDIOPASS $F "${PLOG[@]}"
            next_vobsub_idx
            if ((PASS==2)); then
                ((DEBUG)) && debug_line $((LINENO+2)) "PASS 2/$PASS"
                me_log
                mencoder     $OPTIONS ${VIDEOPASS}:vpass=2 "${RAWVIDEO[@]}"   "${SID[@]}" "${MENCODERARG[@]}" $AID $AUDIOPASS $F "${PLOG[@]}" "${MSG[@]}" \
                  >"$output".fifo
                next_vobsub_idx
            else
                for ((a=2;a<PASS;a++)); do
                    ((DEBUG)) && debug_line $((LINENO+1)) "PASS $a/$PASS"
                    mencoder $OPTIONS ${VIDEOPASS}:vpass=3 -o /dev/null       "${SID[@]}" "${MENCODERARG[@]}" $AID $AUDIOPASS $F "${PLOG[@]}"
                    next_vobsub_idx
                done
                ((DEBUG)) && debug_line $((LINENO+2)) "PASS $PASS/$PASS"
                me_log
                mencoder     $OPTIONS ${VIDEOPASS}:vpass=3 "${RAWVIDEO[@]}"   "${SID[@]}" "${MENCODERARG[@]}" $AID $AUDIOPASS $F "${PLOG[@]}" "${MSG[@]}" \
                  >"$output".fifo
                next_vobsub_idx
            fi
        fi
        status_bit avi set
    fi
fi

###############################################################################
#### if there are still vobsub to dump, do it now
###############################################################################
while ((${#SID[*]})) ; do
    ((DEBUG)) && debug_line $((LINENO+1)) vobsub
    mencoder -ovc copy -o /dev/null $AID "${SID[@]}" "${MENCODERARG[@]}" -nosound
    next_vobsub_idx
done
if status_bit sub ; then
    if [[ -f $output.sub && -f $output.idx && ${#encsid[*]} -gt 0 ]]; then
        #### reset the subtitles with the wrong timestamp
        awk -v logfile="$(echo "$output" | sed 's/\\/\\\\/g')".log '{
          if($1=="id:")id=" ("$0")"
          if($1=="timestamp:"){
            n=$2;
            sub(/,/,"",n);
            # convert the timestamp in seconds
            m=3600*substr(n,1,index(n,":")-1);
            sub(/[0-9]*:/,"",n);
            m=m+60*substr(n,1,index(n,":")-1);
            sub(/[0-9]*:/,"",n);
            m=m+substr(n,1,index(n,":")-1);
            sub(/[0-9]*:/,"",n);
            m=m+n/1000;
            # .002 is already ok
            if(m+.004<t){
              printf("++ WARN: [encsid] reset bad timestamp sequence: %s %s%s\n",gensub(/[^ ]* /,"",1,gensub(/,.*/,"",1,p)),substr($2,1,length($2)-1),id) >>logfile ;
              id="";
              p=gensub(/ [^ ]* /," 00:00:00:000, ",1,p)" #"p}
            t=m}
          else t=0;
          if(NR>1)print p;
          p=$0
          }
          END{print p}' <"$output".idx >"$output".idx.idx && mv "$output".idx.idx "$output".idx
        status_bit sub set
    fi
fi

###############################################################################
#### if fast mode skip multiplexing
###############################################################################
if [[ $mpeg && $fast ]]; then
    if status_bit mpg ; then
        if [[ ! $extra ]]; then
            rm -f "$output".mpg "${output}"[0-9][0-9].mpg
            status_bit mpv set
            status_bit mpa set
            status_bit mpg set
            mv "$output".$SUF "$output".mpg
        fi
    fi
fi

###############################################################################
#### split the MPEG stream (for MPEG Mode)
###############################################################################
if status_bit spl ; then
    #### split for MPEG Mode (MPEG-4 codec not supported)
    #### MEncoder does not support split as does mpeg2enc/mplex
    #### this solution is slow, but it seems quite accurate
    if [[ $mpeg && $split && $vcodec != mpeg4 ]]; then
        [[ ! $fast ]] && mv "$output"01.mpg "$output".mpg
        file_size "$output".mpg
        if ((split*1024*1024<fsize)); then
            chunks=$((fsize/(split*1024*1024)+1))
            CLEAN[${#CLEAN[*]}]="$output".framelist
            mplayer "$output".mpg -vf framestep=I -vo null -nosound -benchmark 2>/dev/null | tr '\015' '\012' | \
              awk '{if($1=="I!")print t,substr(f,1,index(f,"/")-1);t=$2;f=$3}' >"$output".framelist
            m=0
            #### removed -vc dummy
            [[ $multiaudio ]] && a=$(mplayer -vo null -ao null -frames 1 -v "$output".mpg 2>/dev/null | awk '/==> Found audio str/{print $NF}' | \
              sort -n | tr '\012' ',' | sed 's/,$/\n/')
            for ((i=0;i<chunks;i++)); do
                if ((i<chunks-1)); then
                    n=$(mplayer "$output".mpg  -vf framestep=I -vo null -nosound -benchmark 2>/dev/null -sb $(((i+1)*split*1024*1024)) -frames 30 | \
                      tr '\015' '\012' | awk '{if($1=="I!"){print t;exit};t=$2}')
                    n=$(awk '/^'"$n"'/{print $2-1;exit}' <"$output".framelist) #should be -2
                else
                    n=
                fi
                ((DEBUG)) && debug_line $((LINENO+1)) "mpeg_split $((i+1))/$chunks"
                "$PROGFILE" -norc "$output".mpg -o "$output"$(printf "%02d" $((i+1))) -mpegonly -mpeg -encode 0:0:1 -$(echo $frameformat| tr '[:upper:]' '[:lower:]') -nosplit -noshowlog -sb $((i*split*1024*1024)) ${n:+-frames $((n-m))} -a ${mpegaspect:-2} ${multiaudio:+-multiaudio $a} -mc 0
                rm "$output"$(printf "%02d" $((i+1))).log
                m=$n
            done
            rm "$output".mpg
        else
            mv "$output".mpg "$output"01.mpg
        fi
        status_bit spl set
    fi
fi

################################################################################
#### done
################################################################################
exit

