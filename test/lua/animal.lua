animal_voices = {bunny="silence", cow="moo", cat="meow", dog="woof"}
counter = 0
sleeping = false

function sleep()
  sleeping = true
end

function speak(animal)
  return animal_voices[animal]
end

function voices()
  return animal_voices
end

function waste_cycles(n)
  local t = 0
  for i=1,n do
    t = t + i
  end
  return t
end

function talk(n)
  counter = counter + n
  return counter
end
