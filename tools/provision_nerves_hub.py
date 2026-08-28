#!/usr/bin/env python3
"""Write NervesHub credentials into the badge's NVS partition.

nvs_partition_gen.py builds a whole partition image, so this replaces the
:badge namespace rather than editing it. Wifi credentials are taken here for
that reason; the display name and peer list are lost and are re-entered on the
badge.

Needs ESP-IDF on PATH:  . $IDF_PATH/export.sh
"""
import argparse
import csv
import glob
import os
import subprocess
import sys
import tempfile

NVS_OFFSET = "0x9000"
NVS_SIZE = 0x6000
NAMESPACE = "badge"
CHIP = "esp32s3"


def port():
    found = sorted(glob.glob("/dev/cu.usbmodem*"))
    if not found:
        sys.exit("no board found at /dev/cu.usbmodem*")
    if len(found) > 1:
        sys.exit(f"more than one board: {', '.join(found)}")
    return found[0]


def write_csv(path, values):
    with open(path, "w", newline="") as fh:
        out = csv.writer(fh)
        out.writerow(["key", "type", "encoding", "value"])
        out.writerow([NAMESPACE, "namespace", "", ""])
        for key, value in values.items():
            if value is not None:
                out.writerow([key, "data", "string", value])


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--key", required=True, help="NervesHub shared secret key")
    ap.add_argument("--secret", required=True, help="NervesHub shared secret")
    ap.add_argument("--host", help="hub host; defaults to devices.nervescloud.com")
    ap.add_argument("--ssid", help="wifi SSID to write alongside")
    ap.add_argument("--psk", help="wifi passphrase")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    values = {
        "nh_key": args.key,
        "nh_secret": args.secret,
        "nh_host": args.host,
        "wifi_ssid": args.ssid,
        "wifi_psk": args.psk,
    }

    print("This replaces the whole NVS partition.")
    print("The badge's display name and peer list will be erased.")
    if not args.ssid:
        print("No --ssid given, so the saved wifi network goes too.")

    with tempfile.TemporaryDirectory() as work:
        source = os.path.join(work, "nvs.csv")
        image = os.path.join(work, "nvs.bin")
        write_csv(source, values)

        gen = ["nvs_partition_gen.py", "generate", source, image, str(NVS_SIZE)]
        flash = [
            "esptool.py", "--chip", CHIP, "--port", port(),
            "write_flash", NVS_OFFSET, image,
        ]

        if args.dry_run:
            print(" ".join(gen))
            print(" ".join(flash))
            return

        subprocess.run(gen, check=True)
        subprocess.run(flash, check=True)

    print("Provisioned. Power-cycle the badge.")


if __name__ == "__main__":
    main()
