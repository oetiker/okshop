$(document).ready(function() {
    $('select').material_select();
    $('.modal').modal();
    $(".button-collapse").sideNav();
    var setPicHeight = function(){
        var maxHeight = 0;
        if ( $(window).width() < 601){
            $('#project-list .card.horizontal').css('height','auto');
            return;
        }
        $('#project-list .card.horizontal').css('height','auto').each(function(){
            maxHeight = Math.max($(this).height(),maxHeight);
        }).css('height',(maxHeight + 5) + 'px' );
    };
    setPicHeight();
    // $(window).on('resize',setPicHeight);
    // var $pics = $('#pics');
    // var picHeight = function(){
    //     return Math.floor($pics.width());
    // }
    // $pics.slider({
    //         full_width: true,
    //         height: picHeight(),
    //         indicators: false,
    //         transition: 1000,
    //         interval: 4000
    // });
    var $window = $(window);
    var showOrderButton = function(){
        if ($window.height()*1.2 < $window.width()){
            $('#order-button').show();
        }
        else {
            $('#order-button').hide();
        }
    };
    showOrderButton();
    $window.on('resize',function(){
        // var height = picHeight;
        // var $slider = $pics.find('ul.slides').first();
        // $pics.height( height);
        // $slider.height (height);
        showOrderButton();
    });

    var $busy = $('#busypop');
    var showBusy = function(){
        $busy.show();
    };

    var hideBusy = function(){
        $busy.hide();
    };
    hideBusy();
    
    $('#project-list input[type=checkbox]').on('change',function(){
        var $this = $(this);
        var $parent = $this.parent().parent().parent();
        if ($this.prop('checked')){
            $parent.addClass('z-depth-2');
        }
        else {
            $parent.removeClass('z-depth-2');
        }
    });

    var getFormData = function(){
        var data = {
            addr: {}
        };
        $('form#orderform input, form#orderform select').each(function(){
            var $this = $(this);
            var id = $this.prop('id');
            var value = $this.val();
            var match;
            // ignore all card data
            if (id.match(/^(card|calc)/)){
                return;
            }
            if (match = id.match(/^addr_(\S+)/)){
                data.addr[match[1]] = value;
                return;
            }
            if (match = id.match(/^check_(\S+)/)){
                if (!data.orgs){
                    data.orgs = [];
                }
                if ($this.prop('checked')){
                    data.orgs.push(match[1]);
                }
                return;
            }
            if (id){
                data[id] = value;
            }
        });
        return data;
    };

    var updateCost = function(){
        $.ajax('get-cost',{
            dataType: 'json',
            method: 'POST',
            contentType: 'application/json; charset=utf-8',
            data: JSON.stringify(getFormData()),
            success: function(msg){
                var key;
                for (key in msg){
                    $('.cost_' + key).text(msg[key]);
                }
            },
        });
    };

    $('#calendars, #delivery,#addr_country').on('change', updateCost);

    updateCost();



    $('#payform_btn').on('click',function(e){
        e.preventDefault();
        e.stopPropagation();
        showBusy();
        $.ajax('check-data',{
            dataType: 'json',
            method: 'POST',
            contentType: 'application/json; charset=utf-8',
            data: JSON.stringify(getFormData()),
            success: function(msg){
                var err;
                hideBusy();
                if (err = msg.error){
                    if (err.fieldId){
                        var $field = $('#' + err.fieldId);
                        $('#' + err.fieldId + ' + label').attr('data-error',err.msg);
                        $field.addClass('invalid');
                        $('select').material_select();
                        $field[0].scrollIntoView();
                        $field.focus();
                    }
                    else {
                        $('#errorpop .modal-content').html('<h4>Unvollständige Information</h4><div class="flow-text">'+err.msg+'</div>');
                        $('#errorpop').modal('open');
                    }
                    return;
                }
                if (msg.status == 'complete') {
                    $('#thankyoupop').modal({
                        dismissible: false
                    }).modal('open');
                }
                else {
                    $('#payform').modal({
                        dismissible: false
                    }).modal('open');
                }
            },
            error: function(xhr,status){
                hideBusy();
                $('#errorpop .modal-content')
                    .html('<h4>Error</h4><p class="flow-text">'+status+'</p>');
                $('#errorpop').modal('open');
                return;
            }
        });
        return false;
    });

    $('#shoporder_btn').on('click',function(e){
        e.preventDefault();
        e.stopPropagation();
        showBusy();
        $.ajax('process-shop-payment',{
            dataType: 'json',
            method: 'POST',
            contentType: 'application/json; charset=utf-8',
            data: JSON.stringify(getFormData()),
            success: function(msg){
                hideBusy();
                var err;
                if (err = msg.error){
                    if (err.fieldId){
                        var $field = $('#' + err.fieldId);
                        $('#' + err.fieldId + ' + label').attr('data-error',err.msg);
                        $field.addClass('invalid');
                        $('select').material_select();
                        $field[0].scrollIntoView();
                        $field.focus();
                    }
                    else {
                        $('#errorpop .modal-content').html('<h4>Unvollständige Information</h4><p class="flow-text">'+err.msg+'</p>');
                        $('#errorpop').modal('open');
                    }
                    return;
                }
                $('#thankyoupop').modal({
                    dismissible: false
                }).modal('open');
            },
            error: function(xhr,status){
                hideBusy();
                $('#errorpop .modal-content')
                    .html('<h4>Error</h4><p class="flow-text">'+status+'</p>');
                $('#errorpop').modal('open');
                return;
            }
        });
        return false;
    });
    var stripe = window.stripeObj;
    var elements = stripe.elements();
    var card = elements.create('card',{
        hidePostalCode: true
    });
    card.on('change', event => {
        let displayError = document.getElementById('card-errors');
        if (event.error) {
          displayError.textContent = error.message;
        } else {
          displayError.textContent = '';
        }
        $('#order_btn').prop('disabled', !event.complete);
    });
    $('#order_btn').prop('disabled',true);
    card.mount('#card-element');
    $('#order_btn').on('click',function(e){
        showBusy();
        e.preventDefault();
        e.stopPropagation();
        var formData = getFormData();
        $.ajax('create-intent',{
            dataType: 'json',
            method: 'POST',
            contentType: 'application/json; charset=utf-8',
            data: JSON.stringify(formData),
            error: function(xhr,status){
                hideBusy();
                $('#errorpop .modal-content')
                    .html('<h4>Error</h4><p class="flow-text">'+status+'</p>');
                $('#errorpop').modal('open');
                return;
            },
            success: function(intent) {
                var err;
                if (err = intent.error){
                    $('#errorpop .modal-content')
                        .html('<h4>Unvollständige Information</h4><p class="flow-text">'+err.msg+'</p>');
                    $('#errorpop').modal('open');
                    return;
                }
                stripe.confirmCardPayment(intent.client_secret, {
                    payment_method: {
                      card: card,
                      billing_details: {
                          address: {
                              postal_code: formData.addr.zip
                          },
                          name: formData.addr.first_name+' '+formData.addr.last_name,
                      }
                    }
                }).then(function(result) {
                    hideBusy();
                    if (result.error) {
                        var msg = result.error.message;
                        if (result.error.decline_code) {
                            msg += ' Decline Code: ' 
                                + result.error.decline_code +'.';
                        }
                        if (result.error.doc_url) {
                            msg += ' <a href="'+result.error.doc_url+'" target="_new">More Information.</a>'
                        }
                        $('#stripeerrorpop .modal-content').html('<h4>Card Validation Problem</h4>'
                        +'<p class="flow-text">'+msg+'</p>');
                        $('#payform').modal('close');
                        $('#stripeerrorpop').modal('open');
                        return;
                    } else {
                        $('#payform').modal('close');
                        $('#thankyoupop').modal({
                            dismissible: false
                        }).modal('open');
                    }
                });
            }
        });
    });
});
