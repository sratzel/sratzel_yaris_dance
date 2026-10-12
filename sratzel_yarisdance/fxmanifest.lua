fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sratzel_yarisdance'
author 'sratzel'
description 'Laeuft "Why\'s this dealer", tanzen alle yaris99 im Umkreis im Takt (Squash & Stretch).'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/beatmap.lua',
}

client_scripts {
    'client/sources.lua',
    'client/dance.lua',
}

server_script 'server/main.lua'

files {
    'audio/whys_this_dealer.mp3',
}

dependencies {
    'ox_lib',
    'xsound',
}
