# Description:
#   Pulls today's MLB games (and scores).
#
# Dependencies:
#   "moment": "^2.6.0"
#
# Commands:
#   hubot baseball - Pulls today's games
#   hubot baseball <team abbreviation> - Pulls today's game for a given team (ex. SF, NYY).
#   hubot baseball standings - Displays the league standings from today
#
# Author:
#   jonursenbach

moment = require 'moment-timezone'

module.exports = (robot) =>
  robot.respond /baseball( \w*)?( [+\-]?[0-9]+)?/i, (msg) ->
    if msg.match[1] && msg.match[1].toLowerCase().trim() == 'standings'
      today = moment()

      url = "http://mlb.mlb.com/lookup/json/named.standings_schedule_date.bam?season=#{today.format('YYYY')}&schedule_game_date.game_date='#{today.format('YYYY')}/#{today.format('MM')}/#{today.format('DD')}'&sit_code='h0'&league_id=103&league_id=104&all_star_sw='N'&version=2"
      msg.http(url).get() (err, res, body) ->
        return msg.send "Unable to pull today's standings. ERROR:#{err}" if err
        return msg.send "Unable to pull today's standings: #{res.statusCode + ':\n' + body}" if res.statusCode != 200
        standings_full = JSON.parse(body)
        standings = standings_full.standings_schedule_date.standings_all_date_rptr.standings_all_date
        teamdata = []
        emit = []
        for league in standings
          teams = league.queryResults.row
          for team in teams
            teamName = padTeamName(team.team_full, team.division)
            divisionHeader = team.division
            divisionHeader += '    W |  L |   Pct | Streak | Run Diff'
            if teamdata.indexOf(divisionHeader) == -1
              msg.send(teamdata.indexOf(divisionHeader))
              teamdata.push(divisionHeader)
            teamdata.push('  '+teamName+'  '+team.w+'|  '+team.l+'|  '+team.pct+' |   '+team.streak+"   |  #{team.runs - team.opp_runs}")

        emit.push("```#{teamdata.join('\n')}```")

        return msg.send emit.join()

    else
      team = if msg.match[1] then msg.match[1].toUpperCase().trim() else false
      days = if msg.match[2] then msg.match[2].split(/[\+\-]/)[1] else false
      if days
        if msg.match[2].match(/\+/)
          today = moment().add(days, 'days')
        else
          today = moment().subtract(days, 'days')
      else
        today = moment()

      url = "http://gd2.mlb.com/components/game/mlb/year_#{today.format('YYYY')}/month_#{today.format('MM')}/day_#{(today).format('DD')}/master_scoreboard.json"
      msg.http(url).get() (err, res, body) ->
        return msg.send "Unable to pull today's scoreboard. ERROR:#{err}" if err
        return msg.send "Unable to pull today's scoreboard: #{res.statusCode + ':\n' + body}" if res.statusCode != 200

        gameday = JSON.parse(body)
        games = gameday.data.games.game

        games.sort (a, b) ->
          if a.linescore
            return -1
          else if a.time < b.time
            return 1

          return 0

        emit = []
        emit.push("For #{today.format('YYYY-MM-DD')}")
        for game in games
          awayTeamName = game.away_team_name
          homeTeamName = game.home_team_name

          if game.linescore
            linescore = game.linescore
            status = game.status

            if displayGame(game, team)
              if !team
                emit.push("#{awayTeamName} (#{linescore.r.away}) vs #{homeTeamName} (#{linescore.r.home}) @ #{game.venue} #{status.ind} #{status.inning}")
                continue

              runs = linescore.r
              hits = linescore.h
              errors = linescore.e

              inningScores = {away: [], home: []}
              awayTeamName = padTeamName(game.away_team_name, game.home_team_name)
              homeTeamName = padTeamName(game.home_team_name, game.away_team_name)

              # If the game is just in the first inning, linecsore.home is an array. Past the first it becomes an array.
              if typeof linescore.inning.home != 'undefined' || typeof linescore.inning.away != 'undefined'
                inningScores.away.push(if linescore.inning.away then linescore.inning.away else ' ')
                inningScores.home.push(if linescore.inning.home then linescore.inning.home else ' ')
              else
                for inning, i in linescore.inning
                  inningScores.away.push(if inning.away then padInningScore(inning.away, i+1) else ' ')
                  inningScores.home.push(if inning.home then padInningScore(inning.home, i+1) else ' ')

              linescoreHeader = []
              linescoreHeader.push(Array(longestTeamName(awayTeamName, homeTeamName).length + 1).join(' '))
              if typeof linescore.inning.home != 'undefined' || typeof linescore.inning.away != 'undefined'
                linescoreHeader.push(1);
              else
                for inning of linescore.inning
                  linescoreHeader.push(parseInt(inning)+1)

              # If there are less than 9 innings, we should pad out the linescore
              if linescoreHeader.length < 10
                for num in [linescoreHeader.length...10]
                  linescoreHeader.push(num);
                  inningScores.away.push(if linescore.inning.away then linescore.inning.away else ' ')
                  inningScores.home.push(if linescore.inning.home then linescore.inning.home else ' ')

              gameLinescore = linescoreHeader.join(' | ') + " ‖ R | H | E | Status \n"
              gameLinescore += awayTeamName + " | " + inningScores.away.join(' | ') + " ‖ #{runs.away} | #{hits.away} | #{errors.away} | #{status.ind} #{status.inning}\n"
              gameLinescore += homeTeamName + " | " + inningScores.home.join(' | ') + " ‖ #{runs.home} | #{hits.home} | #{errors.home} | "

              emit.push("```#{gameLinescore}```");
          else
            if displayGame(game, team)
              emit.push("#{awayTeamName} vs #{homeTeamName} @ #{game.venue} #{localTime(game)}")

        if emit.length >= 1
          return msg.send emit.join("\n")

        msg.send "Sorry, I couldn't find any games today for #{team}."

localTime = (game) ->
  game_time_est   = moment.tz(game.time_date+game.ampm, "YYYY/MM/DD h:mmA", "America/New_York" )
  game_time_local = moment(game_time_est).tz(moment.tz.guess())
  return game_time_local.format("hh:mm A z") 

longestTeamName = (away, home) ->
  if away.length > home.length
    return away
  else
    return home

padTeamName = (team1, team2) ->
  if team1.length < team2.length
    return team1 + Array((team2.length - team1.length) + 1).join(' ')
  else
    return team1

padInningScore = (score, inning) ->
  if inning > 9
    return " "+score
  else
    return score

displayGame = (game, team) ->
  if !team || (team && game.home_name_abbrev == team || game.away_name_abbrev == team)
    return true

  return false
