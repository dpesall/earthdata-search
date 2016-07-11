require 'nokogiri'
require 'open-uri'
require 'json'
require 'colormaps/xml_to_json'
require 'socket'


namespace :colormaps do
  desc "Load colormap data from GIBS"
  task :load => :environment do
    puts "Loading GIBS colormap data..."
    output_dir = "#{Rails.root}/public/colormaps"

    begin
      # if the directory exists, delete it before running the rake task
      # so old/stale colormaps aren't stored b/c GIBS will be updating versions
      puts "removing folder..."
      FileUtils::remove_dir(output_dir)
    rescue Errno::ENOENT
      puts "folder did not exist yet"
    end
    puts "adding folder..."
    FileUtils::mkdir_p(output_dir)

    # regular, OPS url
    gibs_url = "http://map1a.vis.earthdata.nasa.gov/wmts-geo/wmts.cgi/?SERVICE=WMTS&REQUEST=GetCapabilities"
    # SIT url, for testing with colormaps that have xlink:href role v1.2
    # gibs_url = "https://sit.gibs.earthdata.nasa.gov/wmts/epsg4326/all/wmts.cgi?SERVICE=WMTS&REQUEST=GetCapabilities"

    file_count = 0
    error_count = 0

    capabilities_str = open(gibs_url).read
    # This xmlns was breaking xpath queries
    capabilities_file = Nokogiri::XML(capabilities_str.sub('xmlns="http://www.opengis.net/wmts/1.0"', ''))

    layers = capabilities_file.xpath("/Capabilities/Contents/Layer")

    layers.each do |layer|
      id = layer.xpath("./ows:Identifier").first.content.to_s
      # url = layer.xpath("./ows:Metadata/@xlink:href").to_s
      # url = url.gsub(/^https/, 'http') # Avoid SSL errors in CI

      # puts "layer: #{layer}"
      # puts "id: #{id}"
      # puts "url: #{url}"

      # get v1.2 role metadata node
      target = layer.xpath("./ows:Metadata[contains(@xlink:role, '1.2')]")
      # puts "target: #{target}"
      puts "nil: #{target.nil?} | empty: #{target.empty?}"

      if target.empty?
        # layer does not have a metadata node with xlink:role v1.2,
        # so try to use url from another metadata node (no version or v1.0)
        url = layer.xpath("./ows:Metadata/@xlink:href").to_s
      else
        url = target.attribute("href").to_s
      end
      url = url.gsub(/^https/, 'http') # Avoid SSL errors in CI
      puts "url: #{url}"

      unless id.empty? || url.empty? || !url.start_with?('http')
        file_count += 1
        result = Colormaps.xml_to_json(id, url, output_dir)
        error_count += 1 unless result
      end
    end
    puts "#{layers.count} layers"

    puts "#{error_count} error(s), #{file_count} file(s)"

    if error_count > 0
      job = CronJobHistory.new(task_name: 'colormaps:load', last_run: Time.now, status: 'failed', message: "#{error_count} error(s), #{file_count} file(s)", host: Socket.gethostname)
      job.save!
      exit 1
    else
      job = CronJobHistory.new(task_name: 'colormaps:load', last_run: Time.now, status: 'succeeded', host: Socket.gethostname)
      job.save!
    end
  end
end

Rake::Task['db:seed'].enhance ['colormaps:load']
