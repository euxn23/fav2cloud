require 'twitter'
require 'fastimage'
require 'open-uri'
require 'yaml'
require 'dropbox_sdk'


# TODO dropboxAPI, gyazo => tweet_id
class Fav2Cloud
  def initialize
    @config = YAML.load_file('./config.yml')
    connect_twitter
    FileUtils.mkdir_p @config[:local][:path] if @config[:use][:local]
    connect_dropbox if @config[:use][:dropbox]
    fetch_favorites_from_twitter
    save_local if @config[:use][:local]
    post_dropbox if @config[:use][:dropbox]
  end

  def connect_twitter
    keys = @config[:twitter]
    @client = Twitter::REST::Client.new do |config|
      config.consumer_key = keys[:consumer_key]
      config.consumer_secret = keys[:consumer_secret]
      config.access_token = keys[:access_token]
      config.access_token_secret = keys[:access_token_secret]
    end
    @client.user
  rescue => e
    $stderr.puts e
    exit
  end

  def connect_dropbox
    @dropbox = DropboxClient.new(@config[:dropbox][:access_token])
    @dropbox.account_info
  rescue => e
    $stderr.puts e
    exit
  end

  def fetch_favorites_from_twitter
    @media = []
    @favs = []
    max_id = nil

    # fetch favorites until API Rate Limits
    begin
      params = max_id.nil? ? {count: 200} : {count: 200, max_id: max_id}
      @favs += @client.favorites(params)
      max_id = @favs[-1].id-1
    rescue Twitter::Error::TooManyRequests => e
      if @favs.empty?
        $stderr.puts e
        $stderr.puts 'No Favorite fetched.'
        exit
      end
      break
    end while true

    @media.concat @favs.flat_map { |s| s.media }.flat_map { |m|
                    case m
                    when Twitter::Media::AnimatedGif
                      m.video_info.variants.map { |v| v.url.to_s }
                    when Twitter::Media::Photo
                      m.media_url.to_s
                    else
                      []
                    end
                  }
    @media.concat @favs.flat_map { |s| s.urls }.flat_map { |u|
                    if u.display_url. =~ /^instagram\.com\/p\//
                      "#{u.expanded_url}media?size=l"
                    elsif [:bmp, :gif, :jpeg, :png].include? FastImage.type(u.url.to_s)
                      u.expanded_url.to_s
                    else
                      []
                    end
                  }
  end

  def post_dropbox
    dir = '/fav2cloud'
    @media.each do |url|
      file = url =~ /instagram\.com\/p\/(.*)\/media/ ? "#{$1}.jpg" : File.basename(url)
      entity = open(url).open
      path  = "#{dir}/#{file}"
      puts @dropbox.put_file(path, entity)
    end
  end

  def post_evernote

  end

  def save_local
    dir = @config[:local][:path]
    errlog = File.open("#{dir}/errlog", 'w')
    @media.each do |url|
      file = url =~ /instagram\.com\/p\/(.*)\/media/ ? "#{$1}.jpg" : File.basename(url)
      path = "#{dir}/#{file}"
      File.open(path, 'w') do |f|
        begin
          entity = open(url)
          f.write entity.read
        rescue OpenURI::HTTPError => e
          $stderr.puts e
          errlog.puts "#{url} : #{e}"
          f.close
        end
      end
    end
  end
end

Fav2Cloud.new
