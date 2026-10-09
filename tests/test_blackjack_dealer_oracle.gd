extends SceneTree
## Independent exhaustive physical-card chance tree, no solver helpers for values.
const Solver=preload("res://scripts/blackjack_dealer_solver.gd")
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error("DEALER ORACLE: "+label)
func cards(ranks:Array)->Array:
	var out:Array=[]
	for r in ranks:out.append({"rank":r})
	return out
func total(hand:Array)->int:
	var low:=0
	var aces:=0
	for c in hand:
		low+=mini(c.rank,10)
		if c.rank==1:aces+=1
	return low+10 if aces>0 and low+10<=21 else low
func utility(hand:Array,players:Array)->float:
	var result:=0.0
	var dt:=total(hand)
	for p in players:
		if p.bet<=0 or not p.get("result",{}).is_empty():continue
		var pt:=total(p.hand)
		if p.hand.size()==2 and pt==21:result-=2*p.bet
		elif pt>21:result+=p.bet
		elif dt>21:result-=p.bet
		elif hand.size()>=5:
			if p.hand.size()<5:result+=p.bet
		elif p.hand.size()>=5:result-=p.bet
		elif dt>pt:result+=p.bet
		elif dt<pt:result-=p.bet
	return result
func brute(hand:Array,players:Array,shoe:Array)->Dictionary:
	var stop:=utility(hand,players)
	if total(hand)>21 or hand.size()>=5 or shoe.is_empty():return {"action":"stand","stand_ev":stop,"hit_ev":null,"best_ev":stop}
	var hit:=0.0
	# Enumerate physical cards separately, including duplicate ranks, no memoization.
	for i in shoe.size():
		var tail:=shoe.duplicate();var next:=hand.duplicate()
		next.append({"rank":tail.pop_at(i)})
		hit+=brute(next,players,tail).best_ev/float(shoe.size())
	return {"action":"hit" if hit>stop+0.00000001 else "stand","stand_ev":stop,"hit_ev":hit,"best_ev":maxf(stop,hit)}
func counts(shoe:Array)->Array:
	var out:Array=[0,0,0,0,0,0,0,0,0,0]
	for r in shoe:out[mini(r,10)-1]+=1
	return out
func player(hand:Array,bet:int=100)->Dictionary:return {"hand":cards(hand),"bet":bet,"status":"stood","result":{}}
func compare(hand:Array,players:Array,shoe:Array,label:String)->Dictionary:
	var expected:=brute(cards(hand),players,shoe)
	var h:=cards(hand);var cnt:=counts(shoe)
	var before:=JSON.stringify([h,players,cnt])
	var actual:Dictionary=Solver.choose_action(h,players,cnt)
	ck(JSON.stringify([h,players,cnt])==before,label+" input immutable")
	var mass:=0.0
	for probability in actual.outcome_probabilities.values():
		ck(probability>=0.0 and probability<=1.00000001,label+" valid outcome probability")
		mass+=probability
	ck(absf(mass-1.0)<0.00000001,label+" terminal probabilities sum one")
	ck(actual.action==expected.action,label+" action")
	for key in ["stand_ev","hit_ev","best_ev"]:
		if expected[key]==null:
			ck(actual[key]==null,label+" unavailable hit EV");continue
		ck(actual[key]!=null and absf(actual[key]-expected[key])<0.00001,label+" "+key+" actual %s expected %s"%[actual[key],expected[key]])
	return actual
func _initialize()->void:
	for h in [[1,6],[10,7],[10,10],[1,1],[2,2,2,2],[10,9,5],[1,2,8,10]]:
		for ps in [[player([10,8])],[player([2,2,2,2,2])],[player([10,10]),player([8,8],500)],[player([10,10,5]),player([1,10])]]:
			for shoe in [[1],[10],[1,2,10],[2,2,4,10],[1,1,1,9,10],[]]:compare(h,ps,shoe,"small exhaustive %s/%s"%[h,shoe])
	var rng:=RandomNumberGenerator.new();rng.seed=91772
	for i in 100:
		var h:Array=[rng.randi_range(1,10),rng.randi_range(1,10)]
		var ps:Array=[];var shoe:Array=[]
		for j in rng.randi_range(1,4):ps.append(player([rng.randi_range(1,10),rng.randi_range(1,10)],rng.randi_range(1,10)*10))
		for j in rng.randi_range(1,7):shoe.append(rng.randi_range(1,10))
		compare(h,ps,shoe,"random %d"%i)
	var a:=compare([10,7],[player([10,6],1000),player([10,8],10)],[2,10],"weighted stop")
	var b:=compare([10,7],[player([10,6],10),player([10,8],1000)],[2,10],"weighted hit")
	ck(a.action=="stand" and b.action=="hit","bet weights change optimal decision")
	var ps:Array=[player([10,8])]
	var base:Dictionary=Solver.choose_action(cards([1,6]),ps,counts([1,2,3,10]))
	var natural:=player([1,10],10000);natural.result={"outcome":"blackjack","payout":30000};ps.append(natural)
	var paid:Dictionary=Solver.choose_action(cards([1,6]),ps,counts([10,3,2,1]))
	ck(base.action==paid.action and base.best_ev==paid.best_ev,"paid natural constant excluded and card ordering immaterial")
	var tie:=compare([10,7],[player([10,6])],[1],"equal EV tie")
	ck(tie.action=="stand","exact EV tie favors stopping")
	print("INDEPENDENT DEALER ORACLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
