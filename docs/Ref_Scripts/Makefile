# TeensyROM SD card builder
#
# Rebuilds the full card contents from their four upstream sources and writes a
# verified card. See `make help`.
#
# The card layout is NOT the same as the upstream OneLoad64 archive layout, and
# the card deliberately omits ~20,000 files from it (AlternativeFormats, Images,
# xml/tap/ocp dumps, OfficialCRTs *.bin). The `tree` target encodes that mapping.
#
# PLATFORMS
#   macOS    content + card writing.  Tested end to end on real hardware.
#   Linux    content + card writing.  Written carefully, NOT tested by the author.
#   Windows  content only, under Git Bash or MSYS2. Card writing is delegated to
#            PowerShell and is NOT tested by the author.
# Everything that builds the collection is portable. Everything that touches a
# physical disk is per-platform, because there is no portable way to do it.
#
# Requires GNU make (uses ifeq/$(if)/$(strip)). BSD make users: run gmake.

SHELL := /bin/bash
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:

# ------------------------------------------------------------ platform detect

UNAME := $(shell uname -s 2>/dev/null || echo Unknown)

ifeq ($(UNAME),Darwin)
  PLATFORM := macos
else ifeq ($(UNAME),Linux)
  PLATFORM := linux
else ifneq (,$(findstring MINGW,$(UNAME)))
  PLATFORM := windows
else ifneq (,$(findstring MSYS,$(UNAME)))
  PLATFORM := windows
else ifneq (,$(findstring CYGWIN,$(UNAME)))
  PLATFORM := windows
else
  PLATFORM := unknown
endif

# ---------------------------------------------------------------- configuration

BUILD    ?= $(HOME)/.cache/teensyrom
DL       := $(BUILD)/downloads
EX       := $(BUILD)/extract
CARD_SRC ?= $(BUILD)/card

LABEL    ?= TEENSYROM
DISK     ?=
SIZE     ?=
TEST_GB  ?=

HVSC_VER          ?= 81
ONELOAD_GDRIVE_ID ?= 1Ef6J-yyzE14stEaqjK7XlYuutDDBOCyr

HVSC_URL      := https://hvsc.etv.cx/HVSC_$(HVSC_VER)-all-of-them.7z
ONELOAD_URL   := https://drive.usercontent.google.com/download?id=$(ONELOAD_GDRIVE_ID)&export=download&confirm=t
DEMOS_URL     := https://sensoriumembedded.com/tinyweb64/Demos/
TRPLUS_URL    := https://sensoriumembedded.com/tinyweb64/TeensyROM+/TR+%20Demos-Support.zip
AUTOLAUNCH_URL := https://raw.githubusercontent.com/SensoriumEmbedded/TeensyROM/main/docs/autolaunch.txt

HVSC_7Z    := $(DL)/HVSC_$(HVSC_VER)-all-of-them.7z
ONELOAD_7Z := $(DL)/OneLoad64-Games-Collection-v5.7z
TRPLUS_ZIP := $(DL)/TR-Demos-Support.zip

# FAT32 cannot store unix ownership or permissions; plain `rsync -a` errors on it.
RSYNC_FAT  := rsync -rt --no-perms --no-owner --no-group --modify-window=1
RSYNC_EXCL := --exclude='.claude' --exclude='.DS_Store' --exclude='._*' \
              --exclude='.fseventsd' --exclude='.Spotlight-V100' \
              --exclude='System Volume Information' --exclude='\$$RECYCLE.BIN' \
              --exclude='Makefile' --exclude='.git'

# Metadata directories each OS sprinkles on a FAT volume; never counted as ours.
JUNK_FILTER := ! -path '*/.fseventsd/*' ! -path '*/.Spotlight-V100/*' \
               ! -path '*/System Volume Information/*' ! -path '*/.Trash-*/*'

# ------------------------------------------------------- per-platform settings

ifeq ($(PLATFORM),macos)
  # macOS auto-mounts by label under /Volumes.
  MNT        := /Volumes/$(LABEL)
  PLAT_TOOLS := diskutil dot_clean
  DISK_HINT  := disk4          # from `make identify`
endif

ifeq ($(PLATFORM),linux)
  # Linux does not reliably auto-mount, so we mount where we choose. Deterministic.
  MNT        := $(BUILD)/mnt
  PLAT_TOOLS := lsblk parted mkfs.vfat
  DISK_HINT  := sdb            # or mmcblk0
  SUDO       ?= sudo
endif

ifeq ($(PLATFORM),windows)
  # Windows auto-assigns a drive letter; the user supplies it as DRIVE=E.
  DRIVE      ?=
  MNT        := /$(shell echo '$(DRIVE)' | tr 'A-Z' 'a-z' | tr -d ':')
  PLAT_TOOLS := powershell
  DISK_HINT  := 1              # PowerShell disk number
endif

# ------------------------------------------------------------------------ help

.PHONY: help
help:
	@echo 'TeensyROM SD card builder            platform: $(PLATFORM) ($(UNAME))'
	@echo
	@echo 'Build the contents (portable, no card needed, safe):'
	@echo '  make deps                  check required tools are installed'
	@echo '  make fetch                 download all four upstream sources'
	@echo '  make tree                  assemble the curated card tree'
	@echo '  make summary               show what the assembled tree contains'
ifeq ($(PLATFORM),unknown)
	@echo
	@echo 'Card writing is not supported on this platform ($(UNAME)).'
	@echo 'The content targets above still work.'
else ifeq ($(PLATFORM),windows)
	@echo
	@echo 'Write a card (Windows, needs an Administrator shell):'
	@echo '  make identify                     list disks via PowerShell'
	@echo '  make format DISK=1 CONFIRM=yes    ERASES disk 1, assigns a drive letter'
	@echo '  make write  DRIVE=E               copy the tree'
	@echo '  make verify DRIVE=E               checksum every file'
	@echo '  make eject  DRIVE=E'
	@echo '  make card DISK=1 DRIVE=E CONFIRM=yes'
	@echo
	@echo '  NOTE: Windows Format-Volume refuses FAT32 above 32 GB, so SIZE=32G'
	@echo '        is effectively required on larger cards.'
else
	@echo
	@echo 'Write a card (needs DISK=$(DISK_HINT)):'
	@echo '  make identify              list removable disks and their card identity'
	@echo '  make check DISK=$(DISK_HINT)      verify the card is genuine before trusting it'
	@echo '  make format DISK=$(DISK_HINT) CONFIRM=yes    ERASES the card'
	@echo '  make write  DISK=$(DISK_HINT)     copy the tree'
	@echo '  make verify DISK=$(DISK_HINT)     checksum every file against the source'
	@echo '  make eject  DISK=$(DISK_HINT)'
	@echo
	@echo '  make card DISK=$(DISK_HINT) CONFIRM=yes      full pipeline, format through eject'
	@echo
	@echo 'Limit the card to a smaller partition (the TeensyROM docs say 32 GB'
	@echo 'gives the fastest directory reads; the rest is left unallocated):'
	@echo '  make card DISK=$(DISK_HINT) CONFIRM=yes SIZE=32G'
	@echo
	@echo 'Other:'
	@echo '  make test DISK=$(DISK_HINT) CONFIRM=yes      destructive counterfeit capacity test'
	@echo '  make test DISK=$(DISK_HINT) CONFIRM=yes TEST_GB=8   quick partial (cannot detect fakes)'
	@echo '  make rescue DISK=$(DISK_HINT) IMG=~/sd.img   image a failing card'
endif
	@echo
	@echo '  make clean / distclean     remove the tree / also the downloads'
	@echo
	@echo 'Variables: BUILD=$(BUILD)'
	@echo '           CARD_SRC=$(CARD_SRC)'
	@echo '           LABEL=$(LABEL)  HVSC_VER=$(HVSC_VER)'

# ------------------------------------------------------------------ prequisites

.PHONY: deps
deps:
	@missing=; \
	 for t in curl wget 7z rsync unzip $(PLAT_TOOLS); do \
	   command -v $$t >/dev/null 2>&1 || missing="$$missing $$t"; \
	 done; \
	 if [ -n "$$missing" ]; then \
	   echo "missing tools:$$missing"; \
	   case '$(PLATFORM)' in \
	     macos)   echo "install with: brew install wget p7zip rsync";; \
	     linux)   echo "install with: sudo apt install wget p7zip-full rsync parted dosfstools";; \
	     windows) echo "install via MSYS2: pacman -S curl wget p7zip rsync unzip";; \
	     *)       echo "unknown platform $(UNAME) - install the tools above by hand";; \
	   esac; \
	   exit 1; \
	 fi
	@# Recent macOS ships openrsync as /usr/bin/rsync. It lacks --info=stats2 and
	@# --out-format, which `write` and `verify` both depend on.
	@if rsync --version 2>&1 | head -1 | grep -qi openrsync; then \
	   echo "ERROR: $$(command -v rsync) is openrsync, which lacks --info and --out-format."; \
	   echo "Install real rsync (brew install rsync) and put it ahead of /usr/bin in PATH."; \
	   exit 1; \
	 fi
	@echo "all required tools present (platform: $(PLATFORM))"

# ----------------------------------------------------------------- downloading

.PHONY: fetch
fetch: $(HVSC_7Z) $(ONELOAD_7Z) $(TRPLUS_ZIP) $(DL)/autolaunch.txt $(DL)/demos.stamp

$(DL) $(EX):
	@mkdir -p $@

# Downloads go to a .part file first so an interrupted transfer is never mistaken
# for a complete one by make's timestamp check.
$(HVSC_7Z): | $(DL)
	@echo "==> HVSC #$(HVSC_VER)"
	@curl -fSL --retry 3 -o $@.part '$(HVSC_URL)'
	@7z t $@.part >/dev/null || { echo "HVSC archive failed integrity check"; rm -f $@.part; exit 1; }
	@mv $@.part $@

$(ONELOAD_7Z): | $(DL)
	@echo "==> OneLoad64 v5 (554 MB)"
	@curl -fSL --retry 3 -o $@.part '$(ONELOAD_URL)'
	@7z t $@.part >/dev/null || { echo "OneLoad archive failed integrity check"; rm -f $@.part; exit 1; }
	@mv $@.part $@

$(TRPLUS_ZIP): | $(DL)
	@echo "==> TeensyROM+ Demos-Support"
	@curl -fSL --retry 3 -o $@.part '$(TRPLUS_URL)'
	@mv $@.part $@

$(DL)/autolaunch.txt: | $(DL)
	@echo "==> autolaunch.txt"
	@curl -fSL --retry 3 -o $@.part '$(AUTOLAUNCH_URL)'
	@mv $@.part $@

# The demos are served as a plain directory index, so mirror rather than unpack.
$(DL)/demos.stamp: | $(DL)
	@echo "==> Single Load Demos"
	@mkdir -p $(DL)/demos
	@wget -q -nd -np -r -l1 -R 'index.html*' -P $(DL)/demos '$(DEMOS_URL)'
	@rm -f $(DL)/demos/index.html*
	@touch $@

# ----------------------------------------------------------------- extraction

$(EX)/hvsc.stamp: $(HVSC_7Z) | $(EX)
	@echo "==> extracting HVSC"
	@rm -rf $(EX)/hvsc && mkdir -p $(EX)/hvsc
	@7z x -y -o$(EX)/hvsc $< >/dev/null
	@touch $@

$(EX)/oneload.stamp: $(ONELOAD_7Z) | $(EX)
	@echo "==> extracting OneLoad64 (27k files, takes a minute)"
	@rm -rf $(EX)/oneload && mkdir -p $(EX)/oneload
	@7z x -y -o$(EX)/oneload $< >/dev/null
	@touch $@

$(EX)/trplus.stamp: $(TRPLUS_ZIP) | $(EX)
	@echo "==> extracting TR+ Demos-Support"
	@rm -rf $(EX)/trplus && mkdir -p $(EX)/trplus
	@unzip -q -o $< -d $(EX)/trplus
	@touch $@

.PHONY: extract
extract: $(EX)/hvsc.stamp $(EX)/oneload.stamp $(EX)/trplus.stamp

# -------------------------------------------------------------- tree assembly

# Reproduces the card's curation. Counts in comments are for OneLoad64 v5 / HVSC #81.
.PHONY: tree
tree: $(BUILD)/card.stamp

# The stamp lives outside CARD_SRC so it never ends up on the card.
$(BUILD)/card.stamp: $(EX)/hvsc.stamp $(EX)/oneload.stamp $(EX)/trplus.stamp \
                     $(DL)/demos.stamp $(DL)/autolaunch.txt
	@echo "==> assembling card tree at $(CARD_SRC)"
	@rm -rf $(CARD_SRC)
	@mkdir -p '$(CARD_SRC)/OneLoad v5'
	@O=$(EX)/oneload; C='$(CARD_SRC)/OneLoad v5'; \
	 mkdir -p "$$C/Main- MagicDesk CRTs" "$$C/MultiLoad64" "$$C/Dumps" \
	          "$$C/SplashPics" "$$C/Docs" "$$C/Extras"; \
	 echo "    Main- MagicDesk CRTs  <- archive root *.crt"; \
	 rsync -a --include='*.crt' --exclude='*' "$$O/" "$$C/Main- MagicDesk CRTs/"; \
	 echo "    MultiLoad64           <- MultiLoad64/"; \
	 rsync -a "$$O/MultiLoad64/" "$$C/MultiLoad64/"; \
	 echo "    Dumps                 <- Dumps/*.koa + *.sid  (no xml/tap/ocp)"; \
	 rsync -a --include='*.koa' --include='*.KOA' \
	          --include='*.sid' --include='*.SID' \
	          --exclude='*' "$$O/Dumps/" "$$C/Dumps/"; \
	 echo "    SplashPics            <- Dumps/*.koa"; \
	 rsync -a --include='*.koa' --include='*.KOA' --exclude='*' \
	          "$$O/Dumps/" "$$C/SplashPics/"; \
	 echo "    Extras                <- OfficialCRTs (no *.bin) + OtherCRTs  (no Images/)"; \
	 rsync -a --exclude='*.bin' "$$O/Extras/OfficialCRTs/" "$$C/Extras/OfficialCRTs/"; \
	 rsync -a "$$O/Extras/OtherCRTs/" "$$C/Extras/OtherCRTs/"; \
	 echo "    Docs                  <- Docs/"; \
	 rsync -a "$$O/Docs/" "$$C/Docs/"
	@echo "    C64Music              <- HVSC #$(HVSC_VER)"
	@rsync -a $(EX)/hvsc/C64Music/ '$(CARD_SRC)/C64Music/'
	@# zero-byte version marker the original card carried; not part of HVSC itself
	@touch '$(CARD_SRC)/C64Music/HVSC #$(HVSC_VER)'
	@echo "    Demos"
	@mkdir -p '$(CARD_SRC)/Demos'
	@rsync -a $(DL)/demos/ '$(CARD_SRC)/Demos/'
	@echo "    TR+ Demos-Support"
	@rsync -a '$(EX)/trplus/TR+ Demos-Support/' '$(CARD_SRC)/TR+ Demos-Support/'
	@cp -p $(DL)/autolaunch.txt '$(CARD_SRC)/autolaunch.txt'
	@touch $@
	@$(MAKE) --no-print-directory summary

.PHONY: summary
summary:
	@test -d '$(CARD_SRC)' || { echo "no tree yet - run 'make tree'"; exit 1; }
	@echo
	@echo "card tree: $(CARD_SRC)"
	@printf '  %-24s %s\n' 'total files' "$$(find '$(CARD_SRC)' -type f | wc -l | tr -d ' ')"
	@for d in 'OneLoad v5' C64Music Demos 'TR+ Demos-Support'; do \
	   printf '  %-24s %s\n' "$$d" "$$(find "$(CARD_SRC)/$$d" -type f 2>/dev/null | wc -l | tr -d ' ')"; \
	 done
	@printf '  %-24s %s\n' '.crt' "$$(find '$(CARD_SRC)' -name '*.crt' | wc -l | tr -d ' ')"
	@printf '  %-24s %s\n' '.sid' "$$(find '$(CARD_SRC)' -name '*.sid' | wc -l | tr -d ' ')"
	@printf '  %-24s %s\n' 'size' "$$(du -sh '$(CARD_SRC)' | cut -f1)"

# ===========================================================================
#  Everything below this line touches physical disks and is platform-specific.
# ===========================================================================

ifeq ($(PLATFORM),unknown)

.PHONY: identify check format write verify eject card test rescue
identify check format write verify eject card test rescue:
	@echo "Card writing is not supported on $(UNAME)."
	@echo "The content targets (fetch/tree/summary) work fine here; build the tree,"
	@echo "then copy $(CARD_SRC) to a FAT32 card using your platform's tools."
	@exit 1

endif

# --------------------------------------------------------------------- macOS

ifeq ($(PLATFORM),macos)

# Every card target routes through this. It refuses anything that is not a
# removable disk, which is the guard against typing the internal drive.
define require_disk
	@test -n "$(DISK)" || { echo "set DISK=diskN  (see 'make identify')"; exit 1; }
	@diskutil info $(DISK) >/dev/null 2>&1 || { echo "$(DISK): no such disk"; exit 1; }
	@diskutil info $(DISK) | grep -q 'Removable Media: *Removable' || { \
	   echo "REFUSING: $(DISK) is not removable media."; \
	   diskutil info $(DISK) | grep -E 'Device / Media Name|Disk Size'; exit 1; }
endef

# The built-in SD reader reports as "internal, physical", so filtering on
# `diskutil list external` misses it. Filter on removability instead.
.PHONY: identify
identify:
	@found=; \
	 for d in $$(diskutil list | awk '/^\/dev\/disk[0-9]+ /{gsub("/dev/","",$$1); print $$1}'); do \
	   diskutil info $$d 2>/dev/null | grep -q 'Removable Media: *Removable' || continue; \
	   found=yes; \
	   echo "--- $$d (removable) ---"; \
	   diskutil info $$d | grep -E 'Device / Media Name|Disk Size|Volume Name' | sed 's/^ */  /'; \
	 done; \
	 test -n "$$found" || echo '(no removable disks found)'
	@echo
	@echo '--- card identity (built-in reader) ---'
	@# The reader caches the last card's CID after eject. Without a live BSD Name
	@# that CID is stale and describes a card that is no longer present.
	@sp=$$(system_profiler SPCardReaderDataType 2>/dev/null); \
	 if printf '%s\n' "$$sp" | grep -q 'BSD Name'; then \
	   printf '%s\n' "$$sp" | grep -E 'Product Name|Manufacturer ID|Serial Number|Capacity|BSD Name' \
	     | sed 's/^ */  /'; \
	 else \
	   echo '  no card detected (reader link is down).'; \
	   echo '  Any CID the reader still reports is stale - reseat the card.'; \
	 fi

.PHONY: check
check:
	$(require_disk)
	@echo '--- CID identity ---'
	@sp=$$(system_profiler SPCardReaderDataType 2>/dev/null); \
	 name=$$(printf '%s\n' "$$sp" | awk -F': *' '/Product Name/{print $$2}' | head -1); \
	 mfr=$$(printf '%s\n' "$$sp" | awk -F': *' '/Manufacturer ID/{print $$2}' | head -1); \
	 bsd=$$(printf '%s\n' "$$sp" | awk -F': *' '/BSD Name/{print $$2}' | head -1); \
	 $(call cid_verdict)

.PHONY: format
format:
	$(require_disk)
	$(require_confirm)
ifeq ($(strip $(SIZE)),)
	@echo "==> erasing $(DISK) as FAT32/MBR labeled $(LABEL) (full capacity)"
	@diskutil eraseDisk FAT32 $(LABEL) MBRFormat /dev/$(DISK)
else
	@echo "==> partitioning $(DISK): $(SIZE) FAT32 labeled $(LABEL), rest left unallocated"
	@diskutil partitionDisk /dev/$(DISK) MBR FAT32 $(LABEL) $(SIZE) free %noformat% R
endif

# macOS writes AppleDouble sidecars to FAT volumes; the TeensyROM chokes on them.
POST_WRITE = dot_clean -m '$(MNT)'

.PHONY: eject
eject:
	@diskutil eject '$(MNT)' 2>/dev/null || diskutil eject $(DISK)

RAW_DEV = /dev/r$(DISK)
F3_FORMAT = diskutil eraseDisk FAT32 F3TEST MBRFormat /dev/$(DISK) >/dev/null
F3_MNT    = /Volumes/F3TEST

endif

# --------------------------------------------------------------------- Linux

ifeq ($(PLATFORM),linux)

define require_disk
	@test -n "$(DISK)" || { echo "set DISK=sdb (or mmcblk0)  - see 'make identify'"; exit 1; }
	@test -b /dev/$(DISK) || { echo "/dev/$(DISK): not a block device"; exit 1; }
	@rm=$$(cat /sys/block/$(DISK)/removable 2>/dev/null || echo 0); \
	 if [ "$$rm" != "1" ]; then \
	   echo "REFUSING: /dev/$(DISK) is not removable media."; \
	   lsblk -dno NAME,SIZE,MODEL /dev/$(DISK) 2>/dev/null; exit 1; \
	 fi
endef

# mmcblk0/nvme0n1 partitions are p1; sdb partitions are 1. Deliberately avoids a
# `case` statement: the `)` in case patterns is a parsing hazard inside $( ).
PARTSUF = $$(if echo '$(DISK)' | grep -qE '[0-9]$$$$'; then echo p1; else echo 1; fi)

.PHONY: identify
identify:
	@echo '--- removable block devices ---'
	@lsblk -dno NAME,SIZE,RM,MODEL | awk '$$3==1 {printf "  %-12s %-10s %s\n", $$1, $$2, $$4}' \
	  || echo '  (none)'
	@echo
	@echo '--- card identity (native MMC/SD readers only) ---'
	@found=; \
	 for d in /sys/block/mmcblk*/device; do \
	   [ -d "$$d" ] || continue; found=yes; \
	   echo "  $$(basename $$(dirname $$d)):"; \
	   for f in name manfid oemid serial date; do \
	     [ -r "$$d/$$f" ] && printf '    %-8s %s\n' "$$f" "$$(cat $$d/$$f)"; \
	   done; \
	 done; \
	 test -n "$$found" || echo '  (no native MMC reader; USB readers do not expose CID)'

.PHONY: check
check:
	$(require_disk)
	@echo '--- CID identity ---'
	@d=/sys/block/$(DISK)/device; \
	 if [ -r "$$d/name" ]; then \
	   name=$$(cat $$d/name); mfr=$$(cat $$d/manfid 2>/dev/null); bsd='$(DISK)'; \
	   $(call cid_verdict) \
	 else \
	   echo "  no CID available (USB reader?) - cannot authenticate. Use 'make test'."; \
	   test "$(ALLOW_UNKNOWN_CARD)" = yes || exit 1; \
	 fi

.PHONY: format
format:
	$(require_disk)
	$(require_confirm)
	@P=$(PARTSUF); \
	 $(SUDO) umount /dev/$(DISK)$$P 2>/dev/null || true; \
	 $(SUDO) wipefs -a /dev/$(DISK) >/dev/null; \
	 $(SUDO) parted -s /dev/$(DISK) mklabel msdos; \
	 if [ -n '$(strip $(SIZE))' ]; then \
	   echo "==> partitioning $(DISK): $(SIZE) FAT32 labeled $(LABEL), rest left unallocated"; \
	   $(SUDO) parted -s /dev/$(DISK) mkpart primary fat32 1MiB '$(SIZE)'; \
	 else \
	   echo "==> partitioning $(DISK) as FAT32/MBR labeled $(LABEL) (full capacity)"; \
	   $(SUDO) parted -s /dev/$(DISK) mkpart primary fat32 1MiB 100%; \
	 fi; \
	 $(SUDO) parted -s /dev/$(DISK) set 1 lba on; \
	 sleep 2; $(SUDO) partprobe /dev/$(DISK) 2>/dev/null || true; sleep 1; \
	 $(SUDO) mkfs.vfat -F 32 -n '$(LABEL)' /dev/$(DISK)$$P
	@$(MAKE) --no-print-directory mount

.PHONY: mount
mount:
	@mkdir -p '$(MNT)'
	@mountpoint -q '$(MNT)' || \
	   $(SUDO) mount -o uid=$$(id -u),gid=$$(id -g),umask=022 \
	     /dev/$(DISK)$(PARTSUF) '$(MNT)'
	@echo "mounted at $(MNT)"

# Linux creates no AppleDouble sidecars, so nothing to clean.
POST_WRITE = true

.PHONY: eject
eject:
	@sync
	@mountpoint -q '$(MNT)' && $(SUDO) umount '$(MNT)' || true
	@$(SUDO) eject /dev/$(DISK) 2>/dev/null || true
	@echo "ejected $(DISK)"

RAW_DEV = /dev/$(DISK)
F3_FORMAT = $(SUDO) mkfs.vfat -F 32 -n F3TEST /dev/$(DISK)$(PARTSUF) >/dev/null && \
            mkdir -p $(BUILD)/f3mnt && \
            $(SUDO) mount -o uid=$$(id -u) /dev/$(DISK)$(PARTSUF) $(BUILD)/f3mnt
F3_MNT    = $(BUILD)/f3mnt

endif

# ------------------------------------------------------------------- Windows

ifeq ($(PLATFORM),windows)

PS = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command

define require_disk
	@test -n "$(DISK)" || { echo "set DISK=<number>  (see 'make identify')"; exit 1; }
	@bus=$$($(PS) "(Get-Disk -Number $(DISK)).BusType" 2>/dev/null | tr -d '\r'); \
	 case "$$bus" in \
	   SD|USB|MMC) ;; \
	   *) echo "REFUSING: disk $(DISK) has BusType '$$bus', not SD/USB/MMC."; \
	      $(PS) "Get-Disk -Number $(DISK) | Format-List Number,FriendlyName,Size,BusType" 2>/dev/null; \
	      exit 1;; \
	 esac
endef

define require_drive
	@test -n "$(DRIVE)" || { echo "set DRIVE=E (the card's drive letter)"; exit 1; }
	@test -d '$(MNT)' || { echo "$(MNT) not present - is $(DRIVE): mounted?"; exit 1; }
endef

.PHONY: identify
identify:
	@echo '--- disks ---'
	@$(PS) "Get-Disk | Format-Table Number,FriendlyName,@{n='Size(GB)';e={[math]::Round(\$$_.Size/1GB,1)}},BusType,PartitionStyle -AutoSize"
	@echo '--- volumes ---'
	@$(PS) "Get-Volume | Where-Object DriveLetter | Format-Table DriveLetter,FileSystemLabel,FileSystem,@{n='Size(GB)';e={[math]::Round(\$$_.Size/1GB,1)}} -AutoSize"
	@echo 'Windows does not expose the SD CID register; `make check` cannot'
	@echo 'authenticate a card here. Use `make test` instead.'

.PHONY: check
check:
	$(require_disk)
	@echo 'Windows does not expose the SD CID register - cannot authenticate.'
	@echo 'Run `make test DISK=$(DISK) CONFIRM=yes` to verify real capacity instead.'
	@test "$(ALLOW_UNKNOWN_CARD)" = yes || exit 1

# Windows' Format-Volume refuses FAT32 on volumes larger than 32 GB. SIZE=32G
# sidesteps that and is what the TeensyROM docs recommend anyway.
.PHONY: format
format:
	$(require_disk)
	$(require_confirm)
	@echo "==> clearing disk $(DISK) (requires an Administrator shell)"
	@$(PS) "Clear-Disk -Number $(DISK) -RemoveData -RemoveOEM -Confirm:\$$false; \
	        Initialize-Disk -Number $(DISK) -PartitionStyle MBR -ErrorAction SilentlyContinue"
ifeq ($(strip $(SIZE)),)
	@$(PS) "New-Partition -DiskNumber $(DISK) -UseMaximumSize -AssignDriveLetter | \
	        Format-Volume -FileSystem FAT32 -NewFileSystemLabel '$(LABEL)' -Confirm:\$$false"
else
	@$(PS) "New-Partition -DiskNumber $(DISK) -Size $(SIZE)B -AssignDriveLetter | \
	        Format-Volume -FileSystem FAT32 -NewFileSystemLabel '$(LABEL)' -Confirm:\$$false"
endif
	@echo 'Note the assigned drive letter, then: make write DRIVE=<letter>'

POST_WRITE = true

.PHONY: eject
eject:
	$(require_drive)
	@$(PS) "(New-Object -comObject Shell.Application).Namespace(17).ParseName('$(DRIVE):').InvokeVerb('Eject')" \
	  || echo 'eject failed - unmount from Explorer instead'

RAW_DEV   = \\\\.\\PhysicalDrive$(DISK)
F3_FORMAT = @echo 'f3 is not packaged for native Windows; use h2testw instead' && exit 1
F3_MNT    = $(MNT)

endif

# ============================================================ shared card logic

# Shared by macOS and Linux `check`. Expects $$name, $$mfr, $$bsd to be set.
# A genuine card reports a sane product code (SDSN32G, SC32G, ...). Counterfeits
# report garbage - the card that destroyed the original collection said "??asdfg".
define cid_verdict
	 if [ -n "$$bsd" ] && [ "$$bsd" != "$(DISK)" ]; then \
	   echo "  CID above belongs to $$bsd, not $(DISK) - cannot authenticate $(DISK)."; \
	   test "$(ALLOW_UNKNOWN_CARD)" = yes || exit 1; \
	 fi; \
	 if [ -z "$$name" ]; then \
	   echo "  no CID available - cannot authenticate. Use 'make test'."; \
	   test "$(ALLOW_UNKNOWN_CARD)" = yes || exit 1; \
	 else \
	   echo "  Product Name:    $$name"; \
	   echo "  Manufacturer ID: $$mfr"; \
	   if printf '%s' "$$name" | LC_ALL=C grep -qE '^[A-Za-z0-9_-]{3,16}$$'; then \
	     echo "  -> looks genuine"; \
	   else \
	     echo "  -> SUSPECT: nonsense product name indicates a hacked controller."; \
	     echo "     Do not trust data to this card. Override: ALLOW_UNKNOWN_CARD=yes"; \
	     test "$(ALLOW_UNKNOWN_CARD)" = yes || exit 1; \
	   fi; \
	 fi
endef

define require_confirm
	@test "$(CONFIRM)" = yes || { \
	   echo "This ERASES the target disk. Re-run with CONFIRM=yes to proceed."; exit 1; }
endef

ifneq ($(PLATFORM),unknown)

.PHONY: write
write:
	@test -d '$(CARD_SRC)' || { echo "no tree yet - run 'make tree'"; exit 1; }
	@test -d '$(MNT)' || { echo "$(MNT) not mounted - run 'make format' first"; exit 1; }
	@echo "==> writing to $(MNT)"
	@$(RSYNC_FAT) $(RSYNC_EXCL) --info=stats2 '$(CARD_SRC)/' '$(MNT)/' \
	  | grep -E 'Number of (created|regular)|Total file size'
	@$(POST_WRITE)

# Directories always differ on FAT32 (it stores no directory mtime), so only
# regular-file mismatches count as a real failure.
.PHONY: verify
verify:
	@test -d '$(MNT)' || { echo "$(MNT) not mounted"; exit 1; }
	@echo "==> checksumming every file against $(CARD_SRC)"
	@$(RSYNC_FAT) -c --dry-run $(RSYNC_EXCL) --out-format='%n' \
	   '$(CARD_SRC)/' '$(MNT)/' | grep -v '/$$' > $(BUILD)/diffs.txt || true
	@n=$$(wc -l < $(BUILD)/diffs.txt | tr -d ' '); \
	 total=$$(find '$(MNT)' -type f $(JUNK_FILTER) | wc -l | tr -d ' '); \
	 if [ "$$n" -eq 0 ]; then \
	   echo "VERIFIED: 0 mismatches across $$total files"; \
	 else \
	   echo "FAILED: $$n files differ (see $(BUILD)/diffs.txt)"; head -20 $(BUILD)/diffs.txt; exit 1; \
	 fi

.PHONY: card
card: tree check format write verify eject
	@echo
	@echo "card complete and ejected."

# Fills the card and reads it back. This is the real counterfeit test: fakes
# report more capacity than they physically have, so writes past the real size
# either vanish or overwrite earlier data, and f3read catches it.
#
# Full run is slow - roughly 1 hour per 16 GB on a built-in reader. TEST_GB
# limits it to the first N GB for a quick smoke test, but a partial run CANNOT
# detect a fake, because the lie only shows up past the real capacity.
.PHONY: test
test:
	$(require_disk)
	$(require_confirm)
	@command -v f3write >/dev/null || { \
	   echo "f3 not found. macOS: brew install f3   Linux: apt install f3"; exit 1; }
ifeq ($(strip $(TEST_GB)),)
	@echo "==> full-capacity destructive test of $(DISK) - this is the real counterfeit test"
else
	@echo "==> PARTIAL destructive test of $(DISK), first $(TEST_GB) GB only"
	@echo "    NOTE: a partial run cannot detect a counterfeit card."
endif
	@$(F3_FORMAT)
	@echo '--- f3write ---'
	@f3write $(if $(strip $(TEST_GB)),--end-at=$(TEST_GB),) $(F3_MNT)
	@echo '--- f3read ---'
	@f3read $(if $(strip $(TEST_GB)),--end-at=$(TEST_GB),) $(F3_MNT) | tee $(BUILD)/f3.log
	@echo
	@if grep -cE '^ *(Corrupted|Slightly changed|Overwritten): *[1-9]' $(BUILD)/f3.log \
	     >/dev/null 2>&1 && \
	    [ "$$(grep -cE '^ *(Corrupted|Slightly changed|Overwritten): *[1-9]' $(BUILD)/f3.log)" -gt 0 ]; then \
	   echo "FAILED: card reported damaged or fabricated sectors - do not use it."; \
	   exit 1; \
	 fi
	@echo "PASSED: card stored and returned every byte. Full log: $(BUILD)/f3.log"

# Image a failing card before attempting any repair. Repair tools can unmount a
# damaged volume and fail to bring it back - image first, always.
IMG ?= $(HOME)/sd.img
.PHONY: rescue
rescue:
	$(require_disk)
	@command -v ddrescue >/dev/null || { \
	   echo "macOS: brew install ddrescue   Linux: apt install gddrescue"; exit 1; }
	@echo "==> imaging $(RAW_DEV) to $(IMG)"
	@$(SUDO) ddrescue -f -n -b 512 $(RAW_DEV) '$(IMG)' '$(IMG).map'
	@echo "retry pass (Ctrl-C is safe, the map file resumes):"
	@$(SUDO) ddrescue -f -r3 $(RAW_DEV) '$(IMG)' '$(IMG).map'

endif

# ---------------------------------------------------------------------- cleanup

.PHONY: clean distclean
clean:
	rm -rf '$(CARD_SRC)' $(EX) $(BUILD)/card.stamp

distclean: clean
	rm -rf $(BUILD)
