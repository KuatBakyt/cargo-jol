import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/session.dart';
import '../../shared/ui.dart';
import '../orders/order_detail.dart';

class CargoDetail extends StatefulWidget {
  const CargoDetail({super.key, required this.id});
  final int id;
  @override
  State<CargoDetail> createState() => _CargoDetailState();
}
class _CargoDetailState extends State<CargoDetail> {
  late Future<Map<String, dynamic>> future;
  bool busy = false;
  @override
  void initState() { super.initState(); load(); }
  void load() { future = context.read<Session>().api.get('/cargo/${widget.id}'); }
  void refresh() => setState(load);
  Future<void> favorite() async {
    setState(() => busy = true);
    try { await context.read<Session>().api.post('/cargo/${widget.id}/favorite'); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Груз добавлен в избранное'))); }
    catch(e) { if (mounted) showError(context,e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> removeFavorite() async {
    try { await context.read<Session>().api.delete('/cargo/${widget.id}/favorite'); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Груз удалён из избранного'))); }
    catch(e) { if (mounted) showError(context,e); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Карточка груза')), body: PageBody(child: AsyncPanel(future:future,retry:refresh,builder:(cargo) {
    final session = context.watch<Session>();
    final owner = cargo['owner'] == session.userId;
    final shipper = Map<String,dynamic>.from(cargo['shipper'] as Map);
    return ListView(padding:const EdgeInsets.all(24),children:[
      Text('${cargo['from_city']} → ${cargo['to_city']}',style:Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.w800)), const SizedBox(height:16),
      Wrap(spacing:12,children:[StatusChip(cargo['status'] as String), Chip(label:Text(label(cargo['body_type'] as String)))]),const SizedBox(height:16),
      Text(cargo['cargo_name'] as String,style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),Text('${cargo['weight_kg']} кг • ${cargo['volume_m3']} м³'),const SizedBox(height:20),
      ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.trip_origin,color:green),title:Text(cargo['from_address'] as String),subtitle:Text('Загрузка: ${cargo['loading_date']}')),
      ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.location_on_outlined,color:green),title:Text(cargo['to_address'] as String),subtitle:const Text('Адрес разгрузки')),const Divider(height:32),
      Text(money(cargo['price']),style:const TextStyle(fontSize:30,fontWeight:FontWeight.w900,color:green)),const SizedBox(height:12),Text(cargo['description'] as String),const SizedBox(height:20),
      Text('Грузовладелец: ${shipper['first_name']} ${shipper['last_name']}'),Text('Рейтинг ${shipper['rating']} • ${shipper['is_company_verified'] == true ? 'Компания проверена' : 'Компания не проверена'}'),const SizedBox(height:24),
      if (!owner && session.isCarrier && cargo['status'] == 'active') FilledButton.icon(onPressed:() async { await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>MakeOffer(cargo:cargo))); if(mounted)refresh(); },icon:const Icon(Icons.handshake_outlined),label:const Text('Предложить цену')),
      const SizedBox(height:8), Wrap(spacing:8,children:[OutlinedButton.icon(onPressed:busy?null:favorite,icon:const Icon(Icons.bookmark_add_outlined),label:const Text('Сохранить')),TextButton(onPressed:removeFavorite,child:const Text('Убрать из избранного'))]),
      const SizedBox(height:24),Text(owner?'Предложения перевозчиков':'Мои предложения',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:12),OffersPanel(cargoId:widget.id,owner:owner,onChanged:refresh),
      if (owner && ['active','draft'].contains(cargo['status'])) ...[const SizedBox(height:24),TextButton(onPressed:busy?null:()async{
        final yes = await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('Отменить груз?'),content:const Text('Ожидающие предложения будут отклонены.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Назад')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Отменить груз'))]));
        if (yes!=true || !context.mounted) return;
        try { await session.api.patch('/cargo/${widget.id}',{'status':'cancelled'}); if(mounted)refresh(); } catch(e){if(context.mounted)showError(context,e);}
      },child:const Text('Отменить публикацию',style:TextStyle(color:Colors.red)))],
    ]);
  })));
}

class OffersPanel extends StatefulWidget {
  const OffersPanel({super.key,required this.cargoId,required this.owner,required this.onChanged});
  final int cargoId;
  final bool owner;
  final VoidCallback onChanged;
  @override
  State<OffersPanel> createState()=>_OffersPanelState();
}
class _OffersPanelState extends State<OffersPanel> {
  late Future<Map<String,dynamic>> future;
  bool busy=false;
  int page=1;
  @override
  void initState(){super.initState();load();}
  void load(){future=context.read<Session>().api.get('/cargo/${widget.cargoId}/offers',query:{'page':page});}
  @override
  void didUpdateWidget(OffersPanel oldWidget){super.didUpdateWidget(oldWidget);load();}
  Future<void> action(Map<String,dynamic> offer,String action)async{
    setState(()=>busy=true);
    try{
      final api=context.read<Session>().api;
      final response=action=='cancelled'?await api.patch('/offers/${offer['id']}',{'status':'cancelled'}):await api.post('/offers/${offer['id']}/$action');
      if(!mounted)return;
      widget.onChanged();setState(load);
      if(action=='accept')await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>OrderDetail(id:response['id'] as int)));
    }catch(e){if(mounted)showError(context,e);}finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>AsyncPanel(future:future,retry:()=>setState(load),builder:(data){
    final rows=(data['results'] as List).cast<Map<String,dynamic>>();
    if(rows.isEmpty)return const EmptyState('Предложений пока нет',icon:Icons.handshake_outlined);
    return Column(children:[...rows.map((offer){final profile=offer['carrier_profile'] as Map;return Card(elevation:0,child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${profile['first_name']} • ${money(offer['price'])}',style:const TextStyle(fontWeight:FontWeight.w800,fontSize:18)),Text(offer['message'] as String),StatusChip(offer['status'] as String),if(offer['status']=='pending')Wrap(spacing:8,children:widget.owner?[FilledButton(onPressed:busy?null:()=>action(offer,'accept'),child:const Text('Выбрать')),TextButton(onPressed:busy?null:()=>action(offer,'reject'),child:const Text('Отклонить'))]:[TextButton(onPressed:busy?null:()=>action(offer,'cancelled'),child:const Text('Отменить предложение'))])])));}),Row(mainAxisAlignment:MainAxisAlignment.center,children:[IconButton(onPressed:data['previous']==null?null:()=>setState((){page--;load();}),icon:const Icon(Icons.chevron_left)),Text('$page'),IconButton(onPressed:data['next']==null?null:()=>setState((){page++;load();}),icon:const Icon(Icons.chevron_right))])]);
  });
}

class MakeOffer extends StatefulWidget {
  const MakeOffer({super.key,required this.cargo});
  final Map<String,dynamic> cargo;
  @override
  State<MakeOffer> createState()=>_MakeOfferState();
}
class _MakeOfferState extends State<MakeOffer> {
  final form=GlobalKey<FormState>();
  final price=TextEditingController(),message=TextEditingController();
  late Future<Map<String,dynamic>> future;
  int? vehicle;
  bool busy=false;
  @override
  void initState(){super.initState();load();price.text='${widget.cargo['price']}';}
  void load(){future=context.read<Session>().api.get('/vehicles');}
  @override
  void dispose(){price.dispose();message.dispose();super.dispose();}
  Future<void> submit()async{
    if(!form.currentState!.validate())return;
    setState(()=>busy=true);
    try{await context.read<Session>().api.post('/cargo/${widget.cargo['id']}/offers',{'vehicle':vehicle,'price':price.text.replaceAll(',','.'),'message':message.text.trim()});if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Предложение отправлено')));Navigator.pop(context,true);}}
    catch(e){if(mounted)showError(context,e);}finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Предложить цену')),body:PageBody(child:AsyncPanel(future:future,retry:()=>setState(load),builder:(data){
    final rows=(data['results'] as List).cast<Map<String,dynamic>>().where((v)=>v['status']=='available').toList();
    if(rows.isEmpty)return const EmptyState('Сначала добавьте свободную машину в разделе «Профиль».');
    return ListView(padding:const EdgeInsets.all(24),children:[Form(key:form,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text('${widget.cargo['from_city']} → ${widget.cargo['to_city']}',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:24),DropdownButtonFormField<int>(decoration:const InputDecoration(labelText:'Ваша машина'),items:rows.map((v)=>DropdownMenuItem(value:v['id'] as int,child:Text('${v['brand']} ${v['model']} • ${v['plate_number']}'))).toList(),validator:(v)=>v==null?'Выберите машину':null,onChanged:(v)=>vehicle=v),const SizedBox(height:16),FormFieldInput('Ваша цена, ₸',price,number:true,validator:(v){final n=double.tryParse((v??'').replaceAll(',','.'));return n!=null&&n.isFinite&&n>0?null:'Введите цену больше 0';}),FormFieldInput('Сообщение грузовладельцу',message,required:false,lines:3),FilledButton(onPressed:busy?null:submit,child:Text(busy?'Отправляем…':'Отправить предложение'))]))]);
  })));
}
