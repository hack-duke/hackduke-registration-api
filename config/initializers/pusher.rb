require 'pusher'

Pusher.app_id = ENV['PUSHER_']
Pusher.key = ENV['PUSHER_KEY']
Pusher.secret = ENV['PUSHER_SECRET']
Pusher.logger = Rails.logger
Pusher.encrypted = true
