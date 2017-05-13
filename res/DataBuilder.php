<?php

include_once 'DataParser.php';

class DataBuilder{
	private $keys;
	private $chars;
	private $annotations;
	private $unidata;
	private $config;

	// Don't use these characters as part of the full name
	private $ignoreList = [
		8205, // ZERO WIDTH JOINER
		65039 // VARIATION SELECTOR-16
	];

	/**
	 * @param dp DataParser
	 */
	function __construct($dp) {
		$this->keys = $dp->parseKeys();
		$this->chars = $dp->parseAttributes();
		$this->annotations = $dp->parseAnnotations();
		$this->unidata = $dp->parseUnidata();
		$this->config = $dp->parseConfig();
	}

	function build(){
		$emojis = [];
        $keyboards = $this->config->keyboards;

        $groups = [];

		// First pass
		foreach ($this->keys as $key) {
			if($key['Type'] != 'fully-qualified') continue;

			if(
				isset($emojis[explode(': ', $key['Name'])[0]]) &&
				(!isset($this->config->nogroup) || !in_array(explode(': ', $key['Name'])[0], $this->config->nogroup))
			){
				$base = explode(': ', $key['Name'])[0];
				if(!isset($emojis[$base]['alternates'])) $emojis[$base]['alternates'] = [];
				$emojis[$base]['alternates'][] = $key['Symbol'];
			} else {
				$emojis[$key['Name']] = [
					'symbol' => $key['Symbol'],
					'group' => $key['Group'],
					'subGroup' => $key['SubGroup'],
					'name' => $key['Name'],
					'code' => $key['Code']
				];
			}
		}
        if(isset($this->config->addons)) foreach ($this->config->addons as $addon) {
            $emojis[$addon->name] = [
                'symbol' => $addon->symbol,
                'group' => $addon->group,
                'subGroup' => $addon->subGroup,
                'name' => $addon->name
            ];
            if(isset($addon->keywords)) $emojis[$addon->name]['keywords'] = $addon->keywords;
        }

		// Second pass (add additional informations if possible)
		foreach ($emojis as &$e) {
            if(!isset($groups[$e['group']])) $groups[$e['group']] = [];
            $groups[$e['group']][$e['subGroup']] = 0;

            if(!isset($e['code'])) $e['code'] = array_map('DataParser::ord', preg_split("##u", $e['symbol'], -1, PREG_SPLIT_NO_EMPTY));

			$e['fullName'] = implode(', ', array_map(function($cp){
					return $this->unidata[$cp]['name'];
				}, array_filter($e['code'], function($code){
					return !in_array($code, $this->ignoreList);
				})));
			
			$e['version'] = floatval($this->chars[$e['code'][0]]['Version']);
			
			if(!isset($e['keywords']) && isset($this->annotations[$e['code'][0]]['keywords']))
				$e['keywords'] = $this->annotations[$e['code'][0]]['keywords'];

            if(isset($this->config->requireFallback)){
                if(
                    (isset($this->config->requireFallback->version) && $e['version'] >= $this->config->requireFallback->version) ||
                    (isset($this->config->requireFallback->sequences) && in_array($e['symbol'], $this->config->requireFallback->sequences)) ||
                    (isset($this->config->requireFallback->characters) && count(array_filter($this->config->requireFallback->characters, function($c)use($e){
                        return $e['symbol'] > $c->from && $e['symbol'] <= $c->to;
                    })) > 0)
                ) $e['fallbackIcon'] = true;
            }
		}
        echo "Got ".count($emojis)." base emojis\n";

        // Keyboards
        foreach ($keyboards as $k) {
            foreach ($k->content as $c) {
                if(!isset($groups[$c->group])) echo "[WARNING] Keyboard ".$k->name.": group ".$c->group." doesn't exist\n";
                elseif(!isset($groups[$c->group][$c->subGroup])) echo "[WARNING] Keyboard ".$k->name.": subgroup ".$c->group.'.'.$c->subGroup." doesn't exist\n";
                else $groups[$c->group][$c->subGroup]++;
            }
        }
        foreach ($groups as $g => $sub) {
            foreach ($sub as $s => $n) {
                if($n == 0) echo "[WARNING] Subgroup $g.$s is not used on any keyboard.\n";
                elseif($n > 1) echo "[WARNING] Subgroup $g.$s is used more than once.\n";
            }
        }

		$data = [
            'emojis' => array_values($emojis),
            'keyboards' => $keyboards
        ];
		file_put_contents('data/emojis.json', json_encode($data, JSON_PRETTY_PRINT |  JSON_UNESCAPED_UNICODE));
		file_put_contents('data/emojis.min.json', json_encode($data));
        echo "File written in data/emojis.json\n";
		return $data;
	}
}