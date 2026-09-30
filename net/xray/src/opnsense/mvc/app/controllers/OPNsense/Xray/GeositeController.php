<?php

/*
 * Copyright (C) 2026 os-xray contributors
 * All rights reserved. (BSD-2-Clause, see LICENSE in plugin root)
 */

namespace OPNsense\Xray;

class GeositeController extends \OPNsense\Base\IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Xray/geosite');
    }
}
