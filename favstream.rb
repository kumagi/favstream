# -*- coding: utf-8 -*-
require 'ap'
require 'twitter'
require 'logger'
require 'yaml'

$log = Logger.new(STDOUT)
$log.level = Logger::DEBUG

$log.info 'loading configuration start.'
consumer = YAML.load_file('consumer.yaml')
raise 'invalid consumer' if consumer['key'].nil? || consumer['secret'].nil?
consumer['key'].freeze
consumer['secret'].freeze

alphabets = YAML.load_file('alphabets.yaml')
alphabets.each{ |account|
  raise 'word is invalid for ' + account.to_s if account['word'].length != 1
  raise 'token or secret is empty' + account.to_s if account['token'].nil? || account['token_secret'].nil?
}
$log.info 'loading configuration success.'


$log.info 'account authentication start.'
account_map = {}
alphabets.each{ |account|
  account_map[account['word']] ||= []
  begin
    new_account = Twitter.new(:consumer_key => consumer['key'],
                              :consumer_secret => consumer['secret'],
                              :oauth_token => account['token'],
                              :oauth_token_secret => account['token_secret'])
    new_account.user # 認証失敗したらここでraiseするはず
    account_map[account['word']] << new_account
  rescue => e
    ap e
    raise "OAuth authentication failed for #{account}"
  end
}
$log.info 'authentication complete.'

class AccountNotEnough < Exception;end
class String
  def each
    length.times{ |i|
      yield self[i]
    }
  end
end

$log.info 'start favstream...'
favlist = YAML.load_file('favlist.yaml')
loop{
  favlist.each{ |favtarget|
    Twitter::Search.new.containing(favtarget['keyword']).no_retweets.fetch.each{ |tweet|
      Thread.new{
        $log.debug "stream start for [#{tweet.text}]"
        temporary_fav_history = [] # for rollback
        begin
          favtarget['favword'].each{ |a|
            success = false
            account_map[a].each{|account|
              $log.debug "do fav for #{a} by #{account}"
              begin
                account.favorite_create(tweet.id)
              rescue Twitter::Forbidden
                next
              end
              $log.debug "success."
              success = true
              temporary_fav_history << account
              break
            }
            raise AccountNotEnough if success == false
            sleep 3
          }
          $log.info "favstream success for [#{tweet.text}]"
        rescue AccountNotEnough
          temporary_fav_history.each{ |n|
            n.favorite_destroy(tweet.id)
          }
          $log.info "faving failed for [#{tweet.text}]"
          raise
        rescue => e
          ap e
        end
      }
    }
  }
  sleep 180
}
