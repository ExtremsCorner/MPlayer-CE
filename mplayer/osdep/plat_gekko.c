/*
   MPlayer Wii port

   Copyright (C) 2008 dhewg

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the
   Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02110-1301 USA.

   Improved by MplayerCE Team
*/

 
#include "../config.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <ogcsys.h>
#include <ogc/lwp_watchdog.h>
#include <ogc/lwp.h>
#include <debug.h>
#include <wiiuse/wpad.h>

#include <fat.h>
#include <smb.h>

#include <network.h>
#include <errno.h>
#include <di/di.h>
#include "libdvdiso.h"


#include "log_console.h"
#include "gx_supp.h"
#include "plat_gekko.h"

#include "../m_option.h"
#include "../parser-cfg.h"
#include "../get_path.h"

#undef abort
  
bool reset_pressed = false;
bool power_pressed = false;
bool playing_usb = false;
int network_inited = 0;
static bool dvd_mounted = false;
static bool dvd_mounting = false;
static int dbg_network = false;
static int component_fix = false;
static bool exit_automount_thread = false;

//#define CE_DEBUG 1

static char *default_args[] = {
	"sd:/apps/mplayer_ce/mplayer.dol",
	//"loadlist","http://radioplus.dnsalias.org:8000/listen.pls"
    //"-really-quiet",		
	//"-msglevel","all=5",		
    //"-nocache",
	"-really-quiet","-lavdopts","lowres=1,900:fast=1:skiploopfilter=all","-bgvideo", "sd:/apps/mplayer_ce/loop.avi", "-idle", "sd:/apps/mplayer_ce/loop.avi"
	//"-sws","4","-vf","scale=640:-2",
	//"-lavdopts","lowres=1:fast:skiploopfilter=nonkey","dvd://"
    //"-nomenu",
	//"sd:/Crystal_Skull.avi"
	//"sd:/test2.avi"
	//"-sws","4","-vf","scale=640:-2","-lavdopts","fast:skiploopfilter=nonkey","sd:/hires.avi"
	//"sd:/test720p.mp4"
	//"usb:/Appaloosa.avi"
	//"usb:/Crystal_Skull.avi"
	//"usb:/CD1.Quantum.Of.Solace.avi"
	//"usb:/La.Semilla.Del.Mal.avi"
}; 

//extern float movie_aspect;

static void reset_cb (void) {
	reset_pressed = true;
}

static void power_cb (void) {
	power_pressed = true;
}

static void wpad_power_cb (void) {
	power_pressed = true;
}

#include <sys/time.h>
#include <sys/timeb.h>
void gekko_gettimeofday(struct timeval *tv, void *tz) {
/*
      struct timeb timebuffer;
        ftime( &timebuffer );
        tv->tv_sec=timebuffer.time;
        tv->tv_usec=1000*timebuffer.millitm;
*/        
        
	u32 us = ticks_to_microsecs(gettime());

	tv->tv_sec = us / TB_USPERSEC;
	tv->tv_usec = us % TB_USPERSEC;
} 
 
void gekko_abort(void) {
	//printf("abort() called\n");
	plat_deinit(-1);
	exit(-1);
}

void __dec(char *cad){int i;for(i=0;cad[i]!='\0';i++)cad[i]=cad[i]-50;}
void sp(){sleep(5);}

void trysmb();

//// Mounting code
#include <sdcard/wiisd_io.h>
#include <sdcard/gcsd.h>
#include <ogc/usbstorage.h>

const DISC_INTERFACE* sd = &__io_wiisd;
const DISC_INTERFACE* usb = &__io_usbstorage;

static lwp_t mainthread;

static s32 initialise_network() 
{
    s32 result;
    while ((result = net_init()) == -EAGAIN) usleep(500);
    return result;
}

int wait_for_network_initialisation() 
{
	if(network_inited) return 1;
	
	while(1)
	{	
	    if (initialise_network() >= 0) {
	        char myIP[16];
	        if (if_config(myIP, NULL, NULL, true) < 0)
			{
			  if(dbg_network) printf("Error getting ip\n");
			  return 0;
			}
	        else
			{
			  network_inited = 1;
			  if(dbg_network) printf("Netwok initialized. IP: %s\n",myIP);
			  return 1;
			}
	    }
	    if(dbg_network) 
		{
			printf("Error initializing netwok\n");
			break;
		}
		sleep(10);
    }
	
	return 0;
}


bool DVDGekkoMount()
{
	if(dvd_mounted) return true;
	dvd_mounting=true;
	if(WIIDVD_DiscPresent())
	{
		int ret;
		printf("WIIDVD_Unmount\n");
		WIIDVD_Unmount();
		printf("WIIDVD_mount\n");
		ret = WIIDVD_Mount();
		dvd_mounted=true;
		dvd_mounting=false;
		if(ret==-1) return false;
		return true;		
	}
	dvd_mounting=false;
	dvd_mounted=false;
	return false;
}

static void * networkthreadfunc (void *arg)
{
	usleep(100);
	if(wait_for_network_initialisation()) 
	{
		trysmb();
	}
	usleep(100);
	LWP_JoinThread(mainthread,NULL);
	return NULL;
}

#include <sys/iosupport.h>
bool DeviceMounted(const char *device)
{
  devoptab_t *devops;
  int i;
  devops = (devoptab_t*)GetDeviceOpTab(device);
  if (!devops) return false;
  for(i=0;device[i]!='\0' && device[i]!=':';i++);  
  if (!devops || strncmp(device,devops->name,i)) return false;
  return true;
}

static void * mountthreadfunc (void *arg)
{
	int dp, dvd_inserted=0,usb_inserted=0;


	//initialize usb
	usb->startup();
	if(usb->isInserted())		
	{
		if(fatMountSimple("usb",usb)) usb_inserted=1;
	}
	
#ifdef CE_DEBUG
	LWP_JoinThread(mainthread,NULL);
	return NULL;
#endif	
  
	sleep(1);	
	while(!exit_automount_thread)
	{	
		if(!playing_usb)
		{
			dp=usb->isInserted();
			usleep(500); // needed, I don't know why, but hang if it's deleted
			
			if(dp!=usb_inserted)
			{
				usb_inserted=dp;
				if(!dp)
				{
					fatUnmount("usb");
				}else fatMountSimple("usb",usb);
			}
		}//else usb_inserted=1;	
    			
		if(dvd_mounting==false)
		{
			dp=WIIDVD_DiscPresent();
			if(dp!=dvd_inserted)
			{
				dvd_inserted=dp;
				if(!dp)dvd_mounted=false; // eject
			}
		}
		
		sleep(1);
	}
	LWP_JoinThread(mainthread,NULL);
	return NULL;
}

void mount_smb(int number)
{
	
	char* smb_ip=NULL;
	char* smb_share=NULL;
	char* smb_user=NULL;
	char* smb_pass=NULL;
	
	m_config_t *smb_conf;
	m_option_t smb_opts[] =
	{
	    {   NULL, &smb_ip, CONF_TYPE_STRING, 0, 0, 0, NULL },
	    {   NULL, &smb_share, CONF_TYPE_STRING, 0, 0, 0, NULL },    
	    {   NULL, &smb_user, CONF_TYPE_STRING, 0, 0, 0, NULL }, 
	    {   NULL, &smb_pass, CONF_TYPE_STRING, 0, 0, 0, NULL },
	    {   NULL, NULL, 0, 0, 0, 0, NULL }
	};
	char cad[10];
	sprintf(cad,"ip%d",number);smb_opts[0].name=strdup(cad);	
	sprintf(cad,"share%d",number);smb_opts[1].name=strdup(cad);
	sprintf(cad,"user%d",number);smb_opts[2].name=strdup(cad);
	sprintf(cad,"pass%d",number);smb_opts[3].name=strdup(cad);

	/* read configuration */
	smb_conf = m_config_new();
	m_config_register_options(smb_conf, smb_opts);
	m_config_parse_config_file(smb_conf, "sd:/apps/mplayer_ce/smb.conf");
	
	if(smb_ip==NULL || smb_share==NULL) return;

	if(smb_user==NULL) smb_user=strdup("");
	if(smb_pass==NULL) smb_pass=strdup("");
	sprintf(cad,"smb%d",number);
	if(dbg_network)
	{
	 printf("Mounting SMB Share.. ip:%s  smb_share: '%s'  device: %s ",smb_ip,smb_share,cad);		
	 if(!smbInitDevice(cad,smb_user,smb_pass,smb_share,smb_ip)) printf("error \n");
	 else printf("ok \n");
	}
	else
	  smbInitDevice(cad,smb_user,smb_pass,smb_share,smb_ip);
 
}

void trysmb()
{
	int i;
	for(i=1;i<=5;i++) mount_smb(i);

	//to force connection, I don't understand why is needed
	char cad[20];
	DIR_ITER *dp;
	for(i=1;i<=5;i++) 
	{
		dp=diropen(cad); 
		if(dp!=NULL) dirclose(dp);				
	}	
}

int LoadParams()
{
  m_config_t *comp_conf;
	m_option_t comp_opts[] =
	{
	    {   "component_fix", &component_fix, CONF_TYPE_FLAG, 0, 0, 1, NULL},
	    {   "debug_network", &dbg_network, CONF_TYPE_FLAG, 0, 0, 1, NULL},
	    {   NULL, NULL, 0, 0, 0, 0, NULL }
	};		
	
	/* read configuration */
	comp_conf = m_config_new();
	m_config_register_options(comp_conf, comp_opts);
	int ret;
	return m_config_parse_config_file(comp_conf, "sd:/apps/mplayer_ce/mplayer.conf"); 
}

void plat_init (int *argc, char **argv[]) {	
	WIIDVD_Init(); 
	VIDEO_Init();
	
	PAD_Init();

	WPAD_Init();
	WPAD_SetDataFormat(WPAD_CHAN_0, WPAD_FMT_BTNS);
	WPAD_SetIdleTimeout(60);

	SYS_SetResetCallback (reset_cb);
	SYS_SetPowerCallback (power_cb);
	WPAD_SetPowerButtonCallback(wpad_power_cb);
	
	AUDIO_Init(NULL);
	AUDIO_RegisterDMACallback(NULL);
	AUDIO_StopDMA();


	if (!sd->startup() || !fatMountSimple("sd",sd) || !LoadParams())
	{
		GX_InitVideo();
  	log_console_init(vmode, 0);
  	printf("MPlayerCE v.0.4a\n\n");
		printf("SD access failed\n");
		printf("Please review that you have installed MPlayerCE in the rigth folder\n");
		printf("sd:/apps/mplayer_ce\n");
				
		VIDEO_WaitVSync();
		sleep(6);
		if (!*((u32*)0x80001800)) SYS_ResetSystem(SYS_RETURNTOMENU,0,0);
		exit(0);
	}
	
	GX_SetComponentFix(component_fix);  
	GX_InitVideo();

	log_console_init(vmode, 128);

  printf("Loading ");
  char cad[10]={127,130,158,147,171,151,164,117,119,0};
  __dec(cad);
  printf ("\x1b[32m");
	printf("%s",cad);
	printf(" v.0.4a ....\n\n");
  printf ("\x1b[37m");
  

	mainthread=LWP_GetSelf(); 
	lwp_t clientthread;
	 
 	VIDEO_WaitVSync();

	if (vmode->viTVMode & VI_NON_INTERLACE)
		VIDEO_WaitVSync();
		

LWP_CreateThread(&clientthread, mountthreadfunc, NULL, NULL, 0, 80); // auto-mount file system

#ifndef CE_DEBUG  //no network on debug

	if(dbg_network)
	{
		printf("\nDebugging Network\n");
		if(wait_for_network_initialisation()) 
		{
			trysmb();
		}
		printf("Pause for reading (10 seconds)...");
		VIDEO_WaitVSync();
		sleep(10);
	}
	else LWP_CreateThread(&clientthread, networkthreadfunc, NULL, NULL, 0, 80); // network initialization
	
	//log_console_enable_video(false);
	
#endif	

  
	chdir("sd:/apps/mplayer_ce");
	setenv("HOME", "sd:/apps/mplayer_ce", 1);
	setenv("DVDCSS_CACHE", "off", 1);
	setenv("DVDCSS_VERBOSE", "0", 1);
	setenv("DVDREAD_VERBOSE", "0", 1);
	setenv("DVDCSS_RAW_DEVICE", "/dev/di", 1);
	
	 
	*argv = default_args;
	*argc = sizeof(default_args) / sizeof(char *);
	
	if (!*((u32*)0x80001800)) sp(); 
}

void plat_deinit (int rc) {
	exit_automount_thread=true;
	// Not needed to unmount, speed up close, we don't write
/*
	WIIDVD_Close();
	fatUnmount("sd");
	fatUnmount("usb");

	smbClose("smb1");
	smbClose("smb2");
	smbClose("smb3");
	smbClose("smb4");
	smbClose("smb5");
*/

	if (power_pressed) {
		//printf("shutting down\n");
		SYS_ResetSystem(SYS_POWEROFF, 0, 0);
	}
	
	// only needed to debug problems
/*	
	log_console_enable_video(true);

	VIDEO_WaitVSync();

	if (vmode->viTVMode & VI_NON_INTERLACE)
		VIDEO_WaitVSync();

	//if (rc != 0) sleep(5);
	sleep(5);
	log_console_deinit();
*/	
}