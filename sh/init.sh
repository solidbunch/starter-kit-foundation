#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors

echo '
   ::::::::  :::::::::::     :::     :::::::::  ::::::::::: :::::::::: :::::::::
  :+:    :+:     :+:       :+: :+:   :+:    :+:     :+:     :+:        :+:    :+:
  +:+            +:+      +:+   +:+  +:+    +:+     +:+     +:+        +:+    +:+
  +#++:++#++     +#+     +#++:++#++: +#++:++#:      +#+     +#++:++#   +#++:++#:
         +#+     +#+     +#+     +#+ +#+    +#+     +#+     +#+        +#+    +#+
  #+#    #+#     #+#     #+#     #+# #+#    #+#     #+#     #+#        #+#    #+#
   ########      ###     ###     ### ###    ###     ###     ########## ###    ###

                               __  __  _______  _______
                              |  |/  ||_     _||_     _|
                              |     <  _|   |_   |   |
                              |__|\__||_______|  |___|
                                                _
                                              _|_  _      ._   _|  _. _|_ o  _  ._
                                               |  (_) |_| | | (_| (_|  |_ | (_) | |
'

source sh/env/init.sh "$1"