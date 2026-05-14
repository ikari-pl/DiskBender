#!/bin/sh
# fake_gw.sh — minimal gw stub for DiskBender unit tests.
# Emulates just enough of the Greaseweazle 'gw' CLI for the test suite.

CMD=""
DRIVE=""
OUTFILE=""

# Parse command
if [ $# -lt 1 ]; then
  echo "fake_gw: no command given" >&2
  exit 2
fi

CMD="$1"
shift

case "$CMD" in
  read)
    # gw read [--drive X] <file>
    while [ $# -gt 0 ]; do
      case "$1" in
        --drive)
          shift
          DRIVE="$1"
          shift
          ;;
        *)
          OUTFILE="$1"
          shift
          ;;
      esac
    done
    if [ -z "$OUTFILE" ]; then
      echo "fake_gw: read: no output file" >&2
      exit 2
    fi
    # Write a minimal valid Standard DSK image
    # Header: "MV - CPCEMU Disk-File\r\nDisk-Info\r\n" padded to 256 bytes
    # Then one Track Info Block of 256 bytes (1 track, 9 sectors, 512 B each)
    # Track data: 9 * 512 = 4608 bytes of 0xE5
    python3 - "$OUTFILE" <<'PYEOF'
import sys, struct

outfile = sys.argv[1]

# --- DSK Header (256 bytes) per CPCEMU spec ---
# Offsets (all 0-based):
#   0x00-0x21 : signature (34 bytes)
#   0x22-0x2F : creator name (14 bytes)
#   0x30      : number of tracks
#   0x31      : number of sides
#   0x32-0x33 : track size (standard DSK only, big-endian no — it's little-endian)
#   0x34+     : extended track size table (not used for standard DSK)

NUM_TRACKS   = 1
NUM_SIDES    = 1
SECTORS      = 9
SECTOR_BYTES = 512   # size code 2 -> 128 << 2 = 512
# Standard DSK track size = TIB(256) + sectors * sector_bytes
TRACK_SIZE   = 256 + SECTORS * SECTOR_BYTES   # = 4864 bytes

hdr = bytearray(256)
sig = b'MV - CPCEMU Disk-File\r\nDisk-Info\r\n'
hdr[0:len(sig)]   = sig
hdr[0x22:0x30]    = b'fake_gw       '
hdr[0x30]         = NUM_TRACKS
hdr[0x31]         = NUM_SIDES
# Standard DSK: track size at 0x32-0x33 (little-endian)
struct.pack_into('<H', hdr, 0x32, TRACK_SIZE)

# --- Track Info Block (256 bytes) ---
tib = bytearray(256)
tib[0:12]  = b'Track-Info\r\n'
tib[16]    = 0      # track number
tib[17]    = 0      # side number
tib[20]    = 2      # sector size code: 128<<2 = 512 bytes
tib[21]    = SECTORS
tib[22]    = 0x4E   # GAP3 length
tib[23]    = 0xE5   # filler byte

# Sector Info Records start at offset 24 (8 bytes each)
for i in range(SECTORS):
    base = 24 + i * 8
    tib[base]   = 0          # track
    tib[base+1] = 0          # side
    tib[base+2] = 0xC1 + i  # sector ID (CPC DATA C1..C9)
    tib[base+3] = 2          # size code
    tib[base+4] = 0          # FDC ST1
    tib[base+5] = 0          # FDC ST2
    tib[base+6] = 0          # data length lo (standard DSK: unused)
    tib[base+7] = 0          # data length hi

# --- Sector data: SECTORS * SECTOR_BYTES bytes of 0xE5 ---
sector_data = bytes([0xE5]) * (SECTORS * SECTOR_BYTES)

with open(outfile, 'wb') as f:
    f.write(bytes(hdr))
    f.write(bytes(tib))
    f.write(sector_data)

PYEOF
    echo "Track 0.0: read 9 sectors"
    echo "fake_gw: read complete -> $OUTFILE"
    exit 0
    ;;

  write)
    # gw write [--drive X] <file>
    while [ $# -gt 0 ]; do
      case "$1" in
        --drive)
          shift
          DRIVE="$1"
          shift
          ;;
        *)
          OUTFILE="$1"
          shift
          ;;
      esac
    done
    if [ -z "$OUTFILE" ]; then
      echo "fake_gw: write: no input file" >&2
      exit 2
    fi
    if [ ! -f "$OUTFILE" ]; then
      echo "fake_gw: write: file not found: $OUTFILE" >&2
      exit 1
    fi
    echo "Writing $OUTFILE to drive ${DRIVE:-a}..."
    echo "fake_gw: write complete"
    exit 0
    ;;

  info)
    echo "Greaseweazle v1.0 (fake)"
    echo "firmware: 1.0-fake"
    echo "USB: fake device"
    exit 0
    ;;

  *)
    echo "fake_gw: unknown command: $CMD" >&2
    exit 2
    ;;
esac
