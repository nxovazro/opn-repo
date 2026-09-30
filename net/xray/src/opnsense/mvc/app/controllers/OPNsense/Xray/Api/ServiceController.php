<?php

/*
 * Copyright (C) 2026 os-xray contributors
 * All rights reserved. (BSD-2-Clause, see LICENSE in plugin root)
 */

namespace OPNsense\Xray\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;

class ServiceController extends ApiControllerBase
{
    private function run($action, $params = array())
    {
        $backend = new Backend();
        $response = empty($params)
            ? $backend->configdRun('xray ' . $action)
            : $backend->configdpRun('xray ' . $action, $params);
        $decoded = json_decode(trim($response), true);
        if (is_array($decoded)) {
            return $decoded;
        }
        return array('result' => 'ok', 'output' => trim($response));
    }

    public function statusAction()
    {
        $backend = new Backend();
        $out = trim($backend->configdRun('xray status'));
        $running = stripos($out, 'is running') !== false;
        return array('status' => $running ? 'running' : 'stopped', 'output' => $out);
    }

    public function startAction()
    {
        return $this->run('start');
    }

    public function stopAction()
    {
        return $this->run('stop');
    }

    public function restartAction()
    {
        return $this->run('restart');
    }

    /**
     * Regenerate confdir from UI JSON, validate with xray -test, restart.
     */
    public function reconfigureAction()
    {
        return $this->run('reconfigure');
    }

    public function testAction()
    {
        return $this->run('test');
    }

    public function versionAction()
    {
        $backend = new Backend();
        $out = trim($backend->configdRun('xray version'));
        $first = strtok($out, "\n");
        return array('version' => $first, 'output' => $out);
    }
}
