class PersonDecorator < ApplicationDecorator
  delegate_all

  def primary_description
    object.name
  end

  def birthday_and_age
    return nil unless object.born_on?
    h.content_tag :span, class: 'birthday_and_age' do
      h.content_tag(:span, l(object.born_on), class: 'birthday') +
        h.content_tag(:span, h.t(:years_old, years: object.age), class: 'age')
    end
  end

  def user_description
    if object.user.present?
      h.content_tag(:span, object.user, class: 'user')
    else
      h.content_tag(:em, 'None')
    end
  end
end
