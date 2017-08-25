# Copyright 2017 CNRS & Universite de Bordeaux

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import z3
from petri import load_petrinet, constraint_vector, petrinet_lossy
from cpn import reachable, build_cpn_solver
from solver_utils import set_markings_constrained
from upward_sets import update_upward, in_upward, merge_upward
import numpy as np


from petri import get_transitions
from solver_icover import build_limit_solver,add_limit_equations,build_limit_solver_petrinet
from coverability import _omega_marking,pre_upward,sum_norm,non_coverable,check_cpn_coverability_z3

import time 


total_build_time = 0
total_check_time = 0


def limit_non_coverable(transitions, init, targets):
    MAX_TARGETS_SINGLE_TEST = 10
    

    solver,_ = build_limit_solver(transitions,init)
                
    i = 0
    for target in targets:        
        newtarget = []
        for t in target:
            newtarget.append(t[1])
            
        if check_limit_coverability_z3(solver,[newtarget]) == True:

            return False
      
    return True


def check_limit_coverability_z3(solver,target):
    global total_check_time
    global total_build_time
    
    solver.push()                
    
    time_before = time.time()
    add_limit_equations(solver,target)    
    
    time_after = time.time()
    total_build_time += time_after - time_before
    time_before = time.time()
    result = solver.check()

    time_after = time.time()
    total_check_time += time_after - time_before        

    solver.pop()
    
    if result == z3.sat:
        return True
    elif result == z3.unsat:
        return False
    else:
        return None

def limit_coverability(petrinet, init, targets, prune=False, max_iter=None):
    # use state equation
    # add by GLS
    # Verify if non coverable in CPN first
    transitions = get_transitions(petrinet)
    if prune and limit_non_coverable(transitions, init, targets):
        print "result find with non_coverable"
        return False

    # Otherwise, proceed with backward coverability
    def smallest_elems(x):
        return set(sorted(x, key=sum_norm)[:int(10 + 0.2 * len(x))])            
    
    solver,target_vars = build_limit_solver(transitions,init)
                    

    def limit_coverable(markings):        
        return check_limit_coverability_z3(solver, markings)

    
    init_marking = _omega_marking(init)
    basis = {tuple(constraint_vector(m)) for m in targets}
    precomputed = {}
    covered = False
    
    num_iter = 0

   
    while not covered:
        if max_iter is not None and num_iter >= max_iter:
            return None # Unknown result
        else:
            num_iter += 1

        # Compute prebasis                

        #time_before = time.time()
        prebasis = pre_upward(petrinet, basis, precomputed)

        #time_after = time.time()
        #print "time pre upward :", time_after - time_before


        # Coverability pruning        
        #time_before = time.time()
        pruned = {x for x in prebasis if prune and not limit_coverable([x])}
        nbpruned = len(pruned)

        #time_after = time.time()
        #print "time to prune:", time_after - time_before
        
        
        prebasis.difference_update(pruned)

  

        # Continue?
        if len(prebasis) == 0:
            break
        else:        

            prebasis = smallest_elems(prebasis)
            merge_upward(basis, prebasis)
            covered = in_upward(init_marking, basis)
         

        #print "numbers",num_iter,len(prebasis)+nbpruned,nbpruned




    #print "total build time :", total_build_time
    #print "total check time :", total_check_time
    #print "numbers",num_iter,len(prebasis)+nbpruned,nbpruned

    
    return covered



glitch = 0
UUcomp = 0

nbcomp = 0
error = 0

def comparable_coverability(petrinet, init, targets, prune=False, max_iter=None):

    global total_check_time
    global total_build_time
    global UUcomp
    global nbcomp
    global error


    # Verify if non coverable in CPN first
    if prune and non_coverable(petrinet, init, targets):
        print "non_coverable in Q"
        print "result find with non_coverable"
        return False
    
    # Otherwise, proceed with backward coverability
    def smallest_elems(x):
        return set(sorted(x, key=sum_norm)[:int(10 + 0.2 * len(x))])

    solverQ, variables = build_cpn_solver(petrinet, init, targets=None,
                                         domain='N')

    transitions = get_transitions(petrinet)
    solverL,_ = build_limit_solver(transitions,init)
    _, _, target_vars = variables

   

    def comparaison_coverable(markings):
        global glitch
        global UUcomp
        global nbcomp
        global error

        nbcomp += 1
        #print solverQ
        #print solverL
        resQ = check_cpn_coverability_z3(solverQ, target_vars, markings)
        resL = check_limit_coverability_z3(solverL, markings)
    

        if resQ and resL == False:
            print "qcover solver say cover and limit solver say not cover"
            print "impossible"
            print "error"
            #print markings
            
            error +=1
            print
            exit(1)

        if resQ == False and resL:

            glitch +=1
        
            
        return resQ


    
    

    init_marking = _omega_marking(init)

    basis = {tuple(constraint_vector(m)) for m in targets}
    precomputed = {}
    covered = False
    num_iter = 0

    while not covered:
        if max_iter is not None and num_iter >= max_iter:
            return None # Unknown result
        else:
            num_iter += 1

        # Compute prebasis

        print "step :",num_iter


        prebasis = pre_upward(petrinet, basis, precomputed)


        # Coverability pruning
        nbover = glitch
        pruned = {x for x in prebasis if prune and not comparaison_coverable([x])}
        print "nb over ", glitch-nbover
        print "prebasis size : ", len(prebasis)
        print "size of pruned :", len(pruned)
        prebasis.difference_update(pruned)
        

        
        for x in pruned:
            solverQ.add(z3.Or([target_vars[p] < x[p] for p in
                              range(len(x))]))

        # Continue?
        if len(prebasis) == 0:
            break
        else:
            prebasis = smallest_elems(prebasis)
            merge_upward(basis, prebasis)
            covered = in_upward(init_marking, basis)
         
        
        print 


    print "total build time :", total_build_time
    print "total check time :", total_check_time
    print "glitch: ", glitch
    print "error", error
    print "comparison", nbcomp

    return covered



