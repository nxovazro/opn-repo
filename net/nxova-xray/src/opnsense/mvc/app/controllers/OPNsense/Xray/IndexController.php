<?php

/*
 * Copyright (C) 2026 os-xray contributors
 * All rights reserved. (BSD-2-Clause, see LICENSE in plugin root)
 */

namespace OPNsense\Xray;

class IndexController extends \OPNsense\Base\IndexController
{
    public function indexAction()
    {
        $this->response->redirect('/ui/xray/general/index');
    }
}
