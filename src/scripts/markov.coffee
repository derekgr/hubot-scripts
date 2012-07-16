MARKOV_HEADS='hubot:markov:heads'
MARKOV_TAILS='hubot:markov:tails'
MARKOV_CHAINS='hubot:markov:chain'

# Turns [an, array, of, words] into [[an, array, of], [array, of, words]] in triples.
triples = (words) ->
  return if words.length < 3
  words[i..i+2] for i in [0..words.length-3]

# Tokenize an input string.
split = (str) ->
  str.split(/[ ]+/)

chainify = (str, robot) ->
  store = robot.brain.redis

  parts = split str
  return null if parts.length < 3

  head = [parts[0], parts[1]]
  rev = parts.reverse()
  tail = [rev[1], rev[0]]

  robot.logger.debug("MARKOV HEAD: #{head}")
  robot.logger.debug("MARKOV TAIL: #{tail}")

  store.sadd MARKOV_HEADS, head.join(' ')
  store.sadd MARKOV_TAILS, tail.join(' ')

  key = "#{MARKOV_CHAINS}_#{head.join('_')}"
  tuples = triples (split str)
  for tuple in tuples
    [a,b,c] = tuple
    store.lpush key, c
    store.ltrim key, 0, 5000
    robot.logger.debug("MARKOV CHAIN: incr count for #{key} for #{c}")
    key = "#{MARKOV_CHAINS}_#{b}_#{c}"

markov = (msg, robot) ->
  store = robot.brain.redis
  store.srandmember MARKOV_HEADS, (err, reply) ->
    if !reply?
      msg.send "I can't find any head information to start a chain."
    else
      robot.logger.debug("MARKOV HEAD: #{reply}")
      parts = [reply]
      handler = (lastreply) ->
        (err, reply) ->
          if reply?
            robot.logger.debug("NEXT ITEM FOUND: #{reply}")
            parts.push reply
            key = "#{MARKOV_CHAINS}_#{lastreply}_#{reply}"
            robot.logger.debug("MARKOV KEY: #{key}")
            store.llen key, (err, len) ->
              if len == 0
                msg.send(parts.join ' ')
              else
                i = Math.round (Math.random() * (len - 1))
                robot.logger.debug("KEY CHOSEN: #{i}")
                store.lindex key, i, handler(reply)
          else
            msg.send(parts.join ' ')

      lastreply = (reply.split '_')[1]
      key = "#{MARKOV_CHAINS}_#{reply.split(' ').join('_')}"
      robot.logger.debug("MARKOV KEY: #{key}")
      store.llen key, (err, len) ->
        i = Math.round (Math.random() * (len - 1))
        store.lindex key, i, handler(reply.split(' ')[1])

module.exports = (robot) ->
  robot.catchAll (msg) ->
    return unless robot.brain.redis?
    chainify msg.message.text, robot

  robot.respond /markov$/i, (msg) ->
    return unless robot.brain.redis?
    msg.send markov msg, robot

