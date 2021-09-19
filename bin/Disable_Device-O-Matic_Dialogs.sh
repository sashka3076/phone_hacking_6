#!/bin/sh

#  Disable_Device-O-Matic_Dialogs.sh
#  MobileStorageMounter
#
#  Created by Cameron Birse on 6/21/12.
#

#  Device-O-Matic runs as root but fetches this preference from the mobile user (for historical reasons).
#  Because of that, setting the default for disabling dialogs needs to be done by the
#  mobile user.

flag=$1

if [ 0 = $UID ]; then
    echo "Please log in as mobile to disable dialogs. Thank you.\n"
    exit
fi

if [ "YES" = "$1" ]; then
    defaults write com.apple.mobile.device_o_matic DISABLE_DIALOGS -bool YES
else if [ "NO" = "$1" ]; then
    defaults write com.apple.mobile.device_o_matic DISABLE_DIALOGS -bool NO
else
    echo "usage:   Disable_Device-O-Matic_Dialogs.sh [YES|NO]"
    echo "         NOTE: This tool must be run from the mobile user (not root)."
fi
fi
