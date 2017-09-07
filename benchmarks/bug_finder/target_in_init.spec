# Unsafe: p1 is trivialy coverable. 
# Some coverability tools don't check if the target is in the downward closure of the initial markings. And cpre(p1) = emptyset, hence those tools answer wrongly "Safe".

vars
p1

rules

init
    p1 = 1

target
    p1 >= 1
