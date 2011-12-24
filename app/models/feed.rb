require 'jobs/feed_refresh_job'
class Feed < ActiveRecord::Base
  has_many :items, :dependent => :destroy do
    def latest_item
      order('created_at desc').first
    end
  end
  has_many :subscriptions
  has_many :users, :through => :subscriptions
  AGGREGATE_FEED = -1

  validates_presence_of :original_location

  after_create :queue_refresh

  def queue_refresh
    Resque.enqueue(FeedRefreshJob, self.id)
  end

  def self.aggregate_feed_for(user, page)
    page ||= 0
    virtual_feed = Feed.new
    virtual_feed.items = user.feeds.map do |f|
      f.items.order('created_at desc').limit(5).offset(page * 5)
    end.flatten.sort_by {|i| i.created_at.to_i*-1 } #invert baby
    virtual_feed.id = AGGREGATE_FEED
    virtual_feed.title = "All Feeds"
    virtual_feed
  end

  def self.create_from_opml(opml_file, user)
    parsed = Nokogiri.parse(opml_file.read)
    Feed.transaction do
      parsed.css('outline').each do |sub|
        attrs = sub.attributes
        feed = Feed.find_or_initialize_by_original_location(attrs['xmlUrl'].value)
        feed.title = attrs['title'].value
        feed.save! if feed.new_record?
        feed.subscriptions.create(:user => user)
      end
    end
  end

  def self.create_feed(params, user)
    feed = Feed.find_or_initialize_by_original_location(params[:original_location])
    Feed.transaction do
      feed.save! if feed.new_record?
      feed.subscriptions.create(:user => user)
    end

    feed
  end

  def feed
    @feed || Feedzirra::Feed.fetch_and_parse(original_location)
  end

  def virgin?
    last_updated.blank?
  end

  def refresh
    raise unless persisted?
    @feed = nil # clear any cached feed
    self.title = self.feed.title
    self.description = self.feed.description
    Item.import build_items(self.feed)
    self.last_updated = Time.now
    self.items(true)
    self.save
  end

  def as_json(opts)
    for_user = opts.delete :for_user
    super(opts) unless for_user
    hsh = super(opts).merge!({:items => self.items.as_json(for_user)})
    hsh.merge!({:id => 'all'}) if self.id == AGGREGATE_FEED
    hsh
  end

  private
  def build_items(feed)
    freshest_item = self.items.latest_item
    items = []
    feed.entries.each do |external_item|
      if freshest_item && freshest_item.same_as_external?(external_item)
        break
      else
        items << Item.build_from_feed_item(self, external_item)      end
    end
    items
  end
end
