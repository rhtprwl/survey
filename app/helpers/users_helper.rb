module UsersHelper
  include ContactsHelper
  include MessageHelper

  # TODO - credit icons
  # <div>Icons made by <a href="http://www.flaticon.com/authors/freepik" title="Freepik">Freepik</a> from <a href="http://www.flaticon.com" title="Flaticon">www.flaticon.com</a>             is licensed by <a href="http://creativecommons.org/licenses/by/3.0/" title="Creative Commons BY 3.0">CC BY 3.0</a></div>
  # http://www.flaticon.com/search/rhino
  def icon_for_sensitivity level, size: 50
    icon_tag "sensitivity/#{sensitivity_attributes(level)[:icon]}",
      alt: 'user sensitivity level',
      size: size
  end

  def text_for_sensitivity(level)
    sensitivity_attributes(level)[:text]
  end

  def class_for_sensitivity(level)
    sensitivity_attributes(level)[:class]
  end

  def sensitivity_attributes(level)
    case level
    when 10
      Hash[
        icon:  "rhino",
        class: "xthick",
        text:  "A rock feels no pain."
      ]
    when 9
      Hash[
        icon:  "crocodile",
        class: "xthck",
        text:  "I fear nothing. Don't hold back!"
      ]
    when 8
      Hash[
        icon:  "hedgehog",
        class: "thck",
        text:  "I can take it. Bring it on!"
      ]
    when 7
      Hash[
        icon:  "bear",
        class: "thick",
        text:  "Be honest, but not rude."
      ]
    when 6
      Hash[
        icon:  "turtle",
        class: "medium",
        text:  "Keep it constructive!"
      ]
    when 5
      Hash[
        icon:  "crab",
        class: "medium",
        text: "Be real, but polite please."
      ]
    when 4
      Hash[
        icon:  "rabbit",
        class: "thin",
        text:  "I'm new here. Go easy on me."
      ]
    when 3
      Hash[
        icon:  "lamb",
        class: "thin",
        text:  "Gentleness is a virtue."
      ]
    when 2
      Hash[
        icon:  "duckling",
        class: "xthin",
        text: "Take it easy! I have feelings."
      ]
    when 1
      Hash[
        icon:  "teddy_bear",
        class: "xthin",
        text:  "I am a delicate flower, easily crushed."
      ]
    end
  end

  def social_sites(user)
    User.new.attributes.keys.grep(/url_/).collect do |key|
      site = key.gsub(/url_/, '')
      # icon_path = "social/#{site}.png"
      if user.nil?
        path = url = nil
      else
        path = user.send key
        next unless path
        url = "http://#{path}" if path
      end
      # ans << [site, key, icon_path, path, url]
      [site, key, path]
    end.compact
  end

end
