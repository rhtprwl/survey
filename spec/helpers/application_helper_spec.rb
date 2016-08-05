require 'rails_helper'

describe ApplicationHelper do

  describe 'embedded links' do

    before(:all) do
      text = Faker::Lorem.paragraphs(3).join("\n")
      @links = ['www.foo.bar',
                'http://zz.co',
                'https://en.wikipedia.org/wiki/Chunking_(psychology)']
      punctuation = %W(, ; . \n \r) << ''
      @text = @links.inject(text.split) do |words, link|
        random_index = rand(words.length)
        words.insert random_index, link + punctuation.sample
      end.join(' ')
    end

    it 'should be extracted correctly (without trailing punctuation)' do
      found_links = links_in(@text)
      expect(found_links.length).to eq(3)
      @links.each do |link|
        expect(found_links.include? link).to be(true)
      end
    end

    it 'should convert links to <a> tags correctly' do
      found_links = links_in(@text)
      linkified_text = linkify(@text)
      found_links.each do |link|
        expect(linkified_text.include? tag_for_link(link)).to be(true)
      end
    end

  end

end

def tag_for_link link
  href = (link.start_with?('http') ? link : "http://#{link}")
  "<a href=\"#{href}\">#{link}</a>"
end
