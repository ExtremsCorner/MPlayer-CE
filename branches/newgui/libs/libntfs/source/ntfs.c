/**
 * ntfs.c - Simple functionality for startup, mounting and unmounting of NTFS-based devices.
 *
 * Copyright (c) 2009 Rhys "Shareese" Koedijk
 * Copyright (c) 2006 Michael "Chishm" Chisholm
 *
 * This program/include file is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as published
 * by the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program/include file is distributed in the hope that it will be
 * useful, but WITHOUT ANY WARRANTY; without even the implied warranty
 * of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#endif
#ifdef HAVE_ERRNO_H
#include <errno.h>
#endif
#ifdef HAVE_STRING_H
#include <string.h>
#endif

#include "ntfs.h"
#include "ntfsinternal.h"
#include "ntfsfile.h"
#include "ntfsdir.h"
#include "gekko_io.h"

#define MAX_PARTITIONS                  100 /* Maximum partitions to try find */
#define MAX_MOUNT_NAMES                 100 /* Maximum mount names to try use */

// NTFS device driver devoptab
static const devoptab_t devops_ntfs = {
    NULL, /* Device name */
    sizeof (ntfs_file_state),
    ntfs_open_r,
    ntfs_close_r,
    ntfs_write_r,
    ntfs_read_r,
    ntfs_seek_r,
    ntfs_fstat_r,
    ntfs_stat_r,
    ntfs_link_r,
    ntfs_unlink_r,
    ntfs_chdir_r,
    ntfs_rename_r,
    ntfs_mkdir_r,
    sizeof (ntfs_dir_state),
    ntfs_diropen_r,
    ntfs_dirreset_r,
    ntfs_dirnext_r,
    ntfs_dirclose_r,
    ntfs_statvfs_r,
    ntfs_ftruncate_r,
    ntfs_fsync_r,
    NULL /* Device data */
};

int ntfsFindPartitions (const DISC_INTERFACE *interface, sec_t **partitions)
{
    const u64 ntfs_oem_id = cpu_to_le64(0x202020205346544eULL); /* "NTFS    " */
    
    MASTER_BOOT_RECORD mbr;
    PARTITION_RECORD *partition = NULL;
    sec_t partition_starts[MAX_PARTITIONS] = {0};
    int partition_count = 0;
    sec_t part_lba = 0;
    int i;
    
    union {
        u8 buffer[SECTOR_SIZE];
        MASTER_BOOT_RECORD mbr;
        EXTENDED_BOOT_RECORD ebr;
        NTFS_BOOT_SECTOR boot;
    } sector;
    
    // Start the device and check that it is inserted
    if (!interface->startup()) {
        errno = EIO;
        return -1;
    }
    if (!interface->isInserted()) {
        return 0;
    }
    
    // Read the first sector on the device
    if (!interface->readSectors(0, 1, &sector)) {
        errno = EIO;
        return -1;
    }
    
    printf("u8[446] = %i part[4] = %i, u16 = %i, mbr = %i, ebr = %i, prec = %i\n", sizeof ( u8[446] ), sizeof ( PARTITION_RECORD[4] ), sizeof(u16), sizeof(struct _MASTER_BOOT_RECORD), sizeof(struct _EXTENDED_BOOT_RECORD), sizeof(PARTITION_RECORD));
    
    // If this is the devices master boot record
    printf("%i == %i\n", sector.mbr.signature, cpu_to_le16(MBR_SIGNATURE));
    if (sector.mbr.signature == cpu_to_le16(MBR_SIGNATURE)) {
        memcpy(&mbr, &sector, sizeof(MASTER_BOOT_RECORD));
        
        // Search the partition table for all NTFS partitions (max. 4 primary partitions)
        for (i = 0; i < 4; i++) {
            partition = &mbr.partitions[i];
            part_lba = le32_to_cpu(partition->lba_start);
            
            // Figure out what type of partition this is
            switch (partition->type) {
                
                // NTFS partition
                case PARTITION_TYPE_NTFS: {
                    printf("found primary\n");
                    // Read and validate the NTFS partition
                    if (interface->readSectors(part_lba, 1, &sector)) {
                        if (sector.boot.oem_id == ntfs_oem_id) {
                            partition_starts[partition_count] = part_lba;
                            partition_count++;
                        }
                    }
                    break;
                
                }
                
                // DOS 3.3+ or Windows 95 extended partition
                case PARTITION_TYPE_DOS33_EXTENDED:
                case PARTITION_TYPE_WIN95_EXTENDED: {
                    printf("found extended\n");
                    
                    // Walk the extended partition chain, finding all NTFS partitions
                    sec_t ebr_lba = part_lba;
                    while (ebr_lba) {
                            
                        // Read and validate the extended boot record
                        if (interface->readSectors(ebr_lba, 1, &sector)) {
                            if (sector.ebr.signature == cpu_to_le16(EBR_SIGNATURE)) {
                                printf("found extened record\n");
                                
                                // Get the start sector of the current partition
                                // and the next extended boot record in the chain
                                part_lba = le32_to_cpu(sector.ebr.partition.lba_start);
                                ebr_lba = le32_to_cpu(sector.ebr.next_ebr.lba_start);
                                
                                // Check if this patition is NTFS
                                if (interface->readSectors(part_lba, 1, &sector)) {
                                    if (sector.boot.oem_id == ntfs_oem_id) {
                                        printf("found extended ntfs\n");
                                        partition_starts[partition_count] = part_lba;
                                        partition_count++;
                                    }
                                }
                            
                            }
                        }
                        
                    };
                    
                    break;
                    
                }
                    
            }
            
        }
            
    // Else it is assumed this device has no master boot record
    } else {
        printf("no mbr\n");
        
        // Check the first sector on the device for a NTFS partition
        if (sector.boot.oem_id == ntfs_oem_id) {
            printf("found ntfs @ first sector\n");
            partition_starts[partition_count] = 0;
            partition_count++;
         
        // Ugh?, as a last-ditched effort, search the first 8kb of the device for stray NTFS partitions
        } else {
            printf("last ditch search\n");
            for (i = 0; i < 16; i++) {
                if (!interface->readSectors(i + 1, 1, &sector)) {
                    errno = EIO;
                    return -1;
                }
                if (sector.boot.oem_id == ntfs_oem_id) {
                    printf("found ntfs @ sector %i\n", i);
                    partition_starts[partition_count] = i;
                    partition_count++;
                }
            }
            if (!partition_count) ntfs_log_info("your drive sucks\n"); // :P
        }
        
    }

    // Shutdown the device
    /*interface->shutdown();*/
    
    // Return the found partitions (if any)
    if (partition_count > 0) {
        *partitions = (sec_t*)ntfs_alloc(sizeof(sec_t) * partition_count);
        if (*partitions) {
            memcpy(*partitions, partition_starts, sizeof(sec_t) * partition_count);
            return partition_count;
        }
    }
    
    return 0;
}

int ntfsMountAll (ntfs_md **mounts, u16 flags)
{
    const INTERFACE_ID *discs = ntfsGetDiscInterfaces();
    const INTERFACE_ID *disc = NULL;
    ntfs_md _mounts[32];
    ntfs_md mount;
    int mount_count = 0;
    int partition_count;
    sec_t *partitions = NULL;
    int i, j, k;

    // Find and mount all NTFS partitions on all known devices
    for (i = 0; discs[i].name != NULL && discs[i].interface != NULL; i++) {
        disc = &discs[i];
        partition_count = ntfsFindPartitions(disc->interface, &partitions);
        if (partition_count > 0 && partitions) {
            for (j = 0, k = 0; j < partition_count; j++) {
                
                // Set the partition mount details
                mount.interface = disc->interface;
                mount.startSector = partitions[j];

                // Find the next unused mount name
                do {                    
                    if (k++ > MAX_MOUNT_NAMES) {
                        ntfs_free(partitions);
                        errno = EADDRNOTAVAIL;
                        return -1;
                    }
                    sprintf(mount.name, "%s%i", disc->name, k);
                } while (ntfsGetDeviceOpTab(mount.name));

                // Mount the partition
                if (ntfsMount(mount.name, mount.interface, mount.startSector, flags)) {
                    strcpy(_mounts[mount_count].name, mount.name);
                    _mounts[mount_count].interface = mount.interface;
                    _mounts[mount_count].startSector = mount.startSector;
                    mount_count++;
                }
                
            }
            ntfs_free(partitions);
        }
    }
    
    // Return the mounts (if any)
    if (mount_count > 0) {
        *mounts = (ntfs_md*)ntfs_alloc(sizeof(ntfs_md) * mount_count);
        if (*mounts) {
            memcpy(*mounts, _mounts, sizeof(ntfs_md) * mount_count);
            return mount_count;
        }
    }
    
    return 0;
}

int ntfsMountDevice (const DISC_INTERFACE *interface, ntfs_md **mounts, u16 flags)
{
    const INTERFACE_ID *discs = ntfsGetDiscInterfaces();
    const INTERFACE_ID *disc = NULL;
    ntfs_md _mounts[32];
    ntfs_md mount;
    int mount_count = 0;
    int partition_count;
    sec_t *partitions = NULL;
    int i, j, k;
    
    // Find the specified device then find and mount all NTFS partitions on it
    for (i = 0; discs[i].name != NULL && discs[i].interface != NULL; i++) {
        if (discs[i].interface == interface) {
            disc = &discs[i];
            partition_count = ntfsFindPartitions(disc->interface, &partitions);
            for (j = 0, k = 0; j < partition_count; j++) {
                
                // Set the partition mount details
                mount.interface = disc->interface;
                mount.startSector = partitions[j];
                
                // Find the next unused mount name
                do {                    
                    if (k++ > MAX_MOUNT_NAMES) {
                        ntfs_free(partitions);
                        errno = EADDRNOTAVAIL;
                        return -1;
                    }
                    sprintf(mount.name, "%s%i", disc->name, k);
                } while (ntfsGetDeviceOpTab(mount.name));
                
                // Mount the partition
                if (ntfsMount(mount.name, mount.interface, mount.startSector, flags)) {
                    strcpy(_mounts[mount_count].name, mount.name);
                    _mounts[mount_count].interface = mount.interface;
                    _mounts[mount_count].startSector = mount.startSector;
                }
                
            }
            if (partitions) {
                ntfs_free(partitions);
            }
            break;
        }
    }

    // If we couldn't find the device then return with error status
    if (!disc) {
        errno = ENODEV;
        return -1;
    }
    
    // Return the mounts (if any)
    if (mount_count > 0) {
        *mounts = (ntfs_md*)ntfs_alloc(sizeof(ntfs_md) * mount_count);
        if (*mounts) {
            memcpy(*mounts, _mounts, sizeof(ntfs_md) * mount_count);
            return mount_count;
        }
    }

    return 0;
}

bool ntfsMount (const char *name, const DISC_INTERFACE *interface, sec_t startSector, u16 flags)
{
    devoptab_t *devops = NULL;
    char *devname = NULL;
    struct ntfs_device *dev = NULL;
    ntfs_vd *vd = NULL;
    gekko_fd *fd = NULL;

    // Set the local environment
    ntfs_set_locale();
    ntfs_log_set_handler(ntfs_log_handler_stderr);

    // Check that the request mount name is free
    if (ntfsGetDeviceOpTab(name)) {
        errno = EADDRINUSE;
        return false;
    }
    
    // Check that we can at least read from this device
    if (!(interface->features & FEATURE_MEDIUM_CANREAD)) {
        errno = EPERM;
        return false;
    }
    
    // Allocate a devoptab for this device
    devops = ntfs_alloc(sizeof(devoptab_t) + strlen(name) + 1);
    if (!devops) {
        errno = ENOMEM;
        return false;
    }
    
    // Use the space allocated at the end of the devoptab for storing the device name
    devname = (char*)(devops + 1);
    
    // Allocate the device driver descriptor
    fd = (gekko_fd*)ntfs_alloc(sizeof(gekko_fd));
    if (!fd) {
        ntfs_free(devops);
        errno = ENOMEM;
        return false;
    }
    
    // Setup the device driver descriptor
    fd->interface = interface;
    fd->startSector = startSector;
    fd->sectorSize = 0;
    fd->sectorCount = 0;
    
    // Allocate the device driver
    dev = ntfs_device_alloc(name, 0, &ntfs_device_gekko_io_ops, fd);
    if (!dev) {
        ntfs_free(fd);
        ntfs_free(devops);
        return false;
    }
    
    // Allocate the volume descriptor
    vd = (ntfs_vd*)ntfs_alloc(sizeof(ntfs_vd));
    if (!vd) {
        ntfs_device_free(dev);
        ntfs_free(fd);
        ntfs_free(devops);
        errno = ENOMEM;
        return false;
    }
    
    // Setup the volume descriptor
    vd->id = interface->ioType;
    vd->flags = 0;
    vd->uid = 0;
    vd->gid = 0;
    vd->fmask = 0;
    vd->dmask = 0;
    vd->atime = ((flags & NTFS_UPDATE_ACCESS_TIMES) ? ATIME_ENABLED : ATIME_DISABLED);
    vd->showSystemFiles = (flags & NTFS_SHOW_SYSTEM_FILES);
    vd->cwd_ni = NULL;
    
    // Build the mount flags
    if (!(interface->features & FEATURE_MEDIUM_CANWRITE))
        vd->flags |= MS_RDONLY;
    if ((interface->features & FEATURE_MEDIUM_CANREAD) && (interface->features & FEATURE_MEDIUM_CANWRITE))
        vd->flags |= MS_EXCLUSIVE;
    if (flags & NTFS_RECOVER)
        vd->flags |= MS_RECOVER;
    if (flags & NTFS_IGNORE_HIBERFILE)
        vd->flags |= MS_IGNORE_HIBERFILE;
    
    // Mount the device
    vd->vol = ntfs_device_mount(dev, vd->flags);
    if (!vd->vol) {
        switch(ntfs_volume_error(errno)) {
            case NTFS_VOLUME_NOT_NTFS: errno = EINVALPART; break;
            case NTFS_VOLUME_CORRUPT: errno = EINVALPART; break;
            case NTFS_VOLUME_HIBERNATED: errno = EHIBERNATED; break;
            case NTFS_VOLUME_UNCLEAN_UNMOUNT: errno = EDIRTY; break;
            default: errno = EINVAL; break;
        }
        ntfs_free(vd);
        ntfs_device_free(dev);
        ntfs_free(fd);
        ntfs_free(devops);
        return false;
    }
    
    // Initialise the volume lock
    LWP_MutexInit(&vd->lock, false);
    
    // Add the device to the devoptab table
    memcpy(devops, &devops_ntfs, sizeof(devops_ntfs));
    strcpy(devname, name);
    devops->name = devname;
    devops->deviceData = vd;
    AddDevice(devops);
    
    return true;
}

void ntfsUnmount (const char *name, bool force)
{
    devoptab_t *devops = NULL;
    ntfs_vd *vd = NULL;
    
    // Get the device for this mount
    devops = (devoptab_t*)ntfsGetDeviceOpTab(name);
    if (!devops)
        return;
    
    // Perform a quick check to make sure we're dealing with a NTFS-3G controlled device
    if (devops->open_r != devops_ntfs.open_r)
        return;
    
    // Remove the device from the devoptab table
    RemoveDevice(name);
    
    // Get the devices volume descriptor
    vd = (ntfs_vd*)devops->deviceData;
    if (vd) {
        
        // Deinitialise the volume lock
        LWP_MutexDestroy(vd->lock);
        
        // Close the volumes current directory (if any)
        if (vd->cwd_ni) 
            ntfs_inode_close(vd->cwd_ni);
        
        // Unmount and free the volume
        ntfs_umount(vd->vol, force);
        ntfs_free(vd);
        
    }
    
    // Free the devoptab for the device
    ntfs_free(devops);
    
}

const char *ntfsGetVolumeName (const char *name)
{
    devoptab_t *devops = NULL;
    ntfs_vd *vd = NULL;

    // Get the device for this mount
    devops = (devoptab_t*)ntfsGetDeviceOpTab(name);
    if (!devops) {
        errno = ENOENT;
        return NULL;
    }

    // Perform a quick check to make sure we're dealing with a NTFS-3G controlled device
    if (devops->open_r != devops_ntfs.open_r) {
        errno = EINVALPART;
        return NULL;
    }

    // Get the devices volume descriptor
    vd = (ntfs_vd*)devops->deviceData;
    if (!vd) {
        errno = ENODEV;
        return NULL;
    }

    return vd->vol->vol_name;
}

bool ntfsSetVolumeName (const char *name, const char *volumeName)
{
    devoptab_t *devops = NULL;
    ntfs_vd *vd = NULL;
    ntfs_attr_search_ctx *ctx = NULL;
    ATTR_RECORD *attr = NULL;
    ntfschar *label = NULL;
    int label_len;
    
    // Get the device for this mount
    devops = (devoptab_t*)ntfsGetDeviceOpTab(name);
    if (!devops) {
        errno = ENOENT;
        return false;
    }
    
    // Perform a quick check to make sure we're dealing with a NTFS-3G controlled device
    if (devops->open_r != devops_ntfs.open_r) {
        errno = EINVALPART;
        return false;
    }

    // Get the devices volume descriptor
    vd = (ntfs_vd*)devops->deviceData;
    if (!vd) {
        errno = ENODEV;
        return false;
    }
    
    // Get the volumes attribute search context
    ctx = ntfs_attr_get_search_ctx(vd->vol->vol_ni, NULL);
    if (!ctx) {
        return false;
    }

    // Find the volume name attribute (if it exists)
    if (ntfs_attr_lookup(AT_VOLUME_NAME, AT_UNNAMED, 0, 0, 0, NULL, 0, ctx)) {
        attr = NULL;
        if (errno != ENOENT) {
            return false;
        }
    } else {
        attr = ctx->attr;
        if (attr->non_resident) {
            errno = EINVAL;
            return false;
        }
    }

    // Convert the new volume name to unicode
    label_len = ntfsLocalToUnicode(volumeName, &label);
    if (label_len == -1) {
        errno = EINVAL;
        return false;
    }

    // If the volume name attribute exist then update it with the new name
    if (attr) {
        // TODO: resize attr to fit label, set attr value to label
        
    // Else create a new volume name attribute
    } else {
        // TODO: create new attr, set attr value to 'label
    }
    
    // Sync the volume node
    if (ntfs_inode_sync(vd->vol->vol_ni)) {
        ntfs_free(label);
        return false;
    }
    
    // Clean up
    ntfs_free(label);
    
    return true;
}

const devoptab_t *ntfsDeviceOpTab (void)
{
    return &devops_ntfs;
}

const devoptab_t *ntfsGetDeviceOpTab (const char *name)
{
    const devoptab_t *devoptab = NULL;
    int i;
    
    // Search the devoptab table for the specified device name
    // TODO: FIX THIS SO THAT IT DOESN'T CODE DUMP!!!
    for (i = 0; devoptab_list[i] != NULL && devoptab_list[i]->name != NULL; i++) {
        devoptab = devoptab_list[i];
        if (strncmp(name, devoptab->name, strlen(devoptab->name)) == 0) {
            return devoptab;
        }
    }

    return NULL;
}
