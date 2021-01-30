
require 'opus-ruby'

SAMPLERATE = 48000; # In Samples/Second
BITRATE    = 24000; # In kBit/Second

FRAME_SIZE = 0.02;  # In Milliseconds

PACKET_SIZE_BYTES = (FRAME_SIZE * BITRATE / 8.0).ceil;

def create_encoding(filename)
	base_filename = File.basename(filename, '.*');
	file_dir 	  = File.dirname(filename);

	opus_encoder = Opus::Encoder.new(SAMPLERATE, SAMPLERATE * FRAME_SIZE, 1)
	opus_encoder.vbr_rate = 0
	opus_encoder.bitrate = BITRATE

	file_read = `sox "#{filename}" -r #{SAMPLERATE} -c 1 -b 16 -e signed -t raw - 2>/dev/null`
	file_read.force_encoding('ASCII-8BIT')

	read_num_samples = file_read.size() / 2
	read_length  = read_num_samples / SAMPLERATE.to_f

	num_opus_packets = (read_length / FRAME_SIZE).floor

	output_packets = ""

	num_opus_packets.times do
		frame_buffer = file_read.slice!(0, FRAME_SIZE * SAMPLERATE * 2)
		opus_data = opus_encoder.encode(frame_buffer, frame_buffer.size)
		output_packets += opus_data
	end

	output_text = <<~EOT

#include <xasin/audio.h>

static const Xasin::Audio::opus_audio_bundle_t encoded_audio_#{base_filename.gsub(/[^\w\d]/, '_')} = {
	#{PACKET_SIZE_BYTES}, #{output_packets.length / PACKET_SIZE_BYTES}, 255, (const uint8_t[]){
EOT

	newline_counter = 10000;

	output_packets.each_byte do |b|
		if((newline_counter += 1) > 8)
			output_text << "\n\t\t"
			newline_counter = 0;
		end

		output_text << b.to_s << ", "
	end

	output_text << "\n}};"

	File.open("#{file_dir}/#{base_filename}.h", "w") { |f| f.write(output_text) }
end


puts "Finding appropriate source files..."
file_list = `find . -iname *wav`.split("\n")

puts "Found #{file_list.length} files. Generating..."

file_dirs = {}
file_list.each do |fName|
	file_dirs[File.dirname(fName)] ||= []
	file_dirs[File.dirname(fName)] << fName
end

file_dirs.each do |dirname, dir_file_list_unsorted|
	dir_file_list = dir_file_list_unsorted.sort

	dir_file_list.each { |f| create_encoding f }

	File.open("#{dirname}/collection.h", 'w') do |f|
		f.write "\n#include <xasin/audio.h>\n\n"
		f.write(dir_file_list.map do |dirF| 
			"#include \"#{File.basename(dirF, ".*")}.h\""
		end.join("\n"))
	
		f.write "\n\nstatic const Xasin::Audio::OpusCassetteCollection collection_#{dirname[2..-1].gsub(/[^\w\d]/, '_')} = {\n"
		f.write(dir_file_list.map do |dirF| 
			"\tencoded_audio_#{File.basename(dirF, ".*").gsub(/[^\w\d]/, '_')},\n"
		end.join())
		f.write '};'
	end
end