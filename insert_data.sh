#! /bin/bash

if [[ $1 == "test" ]]
then
  PSQL="psql --username=postgres --dbname=worldcuptest -t --no-align -c"
else
  PSQL="psql --username=freecodecamp --dbname=worldcup -t --no-align -c"
fi

# Do not change code above this line. Use the PSQL variable above to query your database.

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
[[ -r games.csv ]] || { printf 'games.csv is missing\n' >&2; exit 1; }

sql_values=''
count=0
while IFS=',' read -r YEAR ROUND WINNER OPPONENT WINNER_GOALS OPPONENT_GOALS || [[ -n "${YEAR:-}" ]]; do
  [[ $YEAR == 'year' || -z $YEAR ]] && continue
  [[ $YEAR =~ ^[0-9]{4}$ && $WINNER_GOALS =~ ^[0-9]+$ && $OPPONENT_GOALS =~ ^[0-9]+$ ]] || {
    printf 'Malformed CSV row %d\n' "$((count + 2))" >&2; exit 1;
  }
  ROUND=${ROUND//\'/\'\'}
  WINNER=${WINNER//\'/\'\'}
  OPPONENT=${OPPONENT//\'/\'\'}
  sql_values+="($YEAR,'$ROUND','$WINNER','$OPPONENT',$WINNER_GOALS,$OPPONENT_GOALS),"
  count=$((count + 1))
done < games.csv

(( count > 0 )) || { printf 'games.csv contains no games\n' >&2; exit 1; }
sql_values=${sql_values%,}

# One SQL invocation for all 32 games. Re-running does not duplicate imported rows.
$PSQL "
CREATE TEMP TABLE wc_import (
  year INTEGER, round VARCHAR(60), winner VARCHAR(60), opponent VARCHAR(60),
  winner_goals INTEGER, opponent_goals INTEGER
);
INSERT INTO wc_import VALUES $sql_values;
INSERT INTO teams (name)
SELECT name FROM (
  SELECT winner AS name FROM wc_import UNION SELECT opponent AS name FROM wc_import
) AS distinct_teams
ON CONFLICT (name) DO NOTHING;
INSERT INTO games (year, round, winner_id, opponent_id, winner_goals, opponent_goals)
SELECT i.year, i.round, w.team_id, o.team_id, i.winner_goals, i.opponent_goals
FROM wc_import AS i
JOIN teams AS w ON w.name = i.winner
JOIN teams AS o ON o.name = i.opponent
WHERE NOT EXISTS (
  SELECT 1 FROM games AS g
  WHERE g.year = i.year AND g.round = i.round
    AND g.winner_id = w.team_id AND g.opponent_id = o.team_id
    AND g.winner_goals = i.winner_goals AND g.opponent_goals = i.opponent_goals
);
" >/dev/null
printf 'Imported %d CSV games into %s\n' "$count" "${1:-worldcup}"
