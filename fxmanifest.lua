fx_version 'cerulean'
game 'gta5'

author 'AntiNoclip Auto Setup'
description 'Server-side noclip detection with API reporting and punishments.'
version '1.0.0'

lua54 'yes'

dependency 'screenshot-basic'

ui_page 'html/index.html'

shared_script 'config.lua'

server_script 'server.lua'
client_script 'client.lua'

files {
    'html/index.html'
}
