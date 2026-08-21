# frozen_string_literal: true

require 'riddles'

# The riddle of the day: everyone gets the same one until midnight, one guess each.
# The cookie carries the last day answered, what was picked, and the streak — a chain
# that only holds if yesterday's was answered too.
class RiddleController < ApplicationController
  def show
    @riddle = Riddles.today(Date.current)
    answered_on, pick, @streak, @best = state
    @answered = answered_on == stamp(Date.current)
    @pick = pick if @answered
  end

  def answer
    answered_on, _pick, streak, best = state
    if answered_on != stamp(Date.current)
      riddle = Riddles.today(Date.current)
      pick = params[:pick].to_i.clamp(0, riddle[:a].length - 1)
      # The chain only holds day to day: a gap starts it over, right answer or not.
      streak = 0 unless answered_on == stamp(Date.current - 1)
      streak = pick == riddle[:right] ? streak + 1 : 0
      best = [best, streak].max
      cookies.permanent['RIDDLE'] = [stamp(Date.current), pick, streak, best].join(' ')
    end
    redirect_to games_riddle_path
  end

  private

  def stamp(date)
    date.strftime('%Y%m%d')
  end

  def state
    answered_on, pick, streak, best = cookies['RIDDLE'].to_s.split
    [answered_on.to_s, pick.to_i, streak.to_i, best.to_i]
  end
end
